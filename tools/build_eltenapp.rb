# frozen_string_literal: true

# Builds an unsigned program package from the src folder, mirroring
# Elten's Programs::UnsignedPackageBuilder (src/eapi/unsigned_package_builder.rb).
# Output format is chosen by extension:
#   .eltenapp — single code container (installed via the Elten app repository);
#   .eltsetup — ZIP setup archive wrapping an .eltenapp payload plus loose
#               resources (the format "Install from file" accepts in Elten).
# Uses zstd-ruby when available, otherwise falls back to the system libzstd
# via Fiddle. Output: build/MileByMile.eltenapp or build/*.eltsetup.
#
# Usage: ruby tools/build_eltenapp.rb [output_path]
# Works both in this container and on a Windows machine with Ruby + zstd-ruby.

require 'json'
require 'zlib'

APP_NAME = 'MileByMile'
MAGIC = 'Elten3AppPackage'
SOUND_EXTENSIONS = %w[.ogg .opus .wav .wave .mp3 .flac .aac .m4a .wma .spx .webm].freeze

module ZstdCompressor
  module_function

  def compress(data, level: 19)
    if defined?(Zstd)
      Zstd.compress(data, :level => level)
    else
      fiddle_compress(data, level)
    end
  end

  def fiddle_compress(data, level)
    require 'fiddle'
    require 'fiddle/import'
    @api ||= begin
      mod = Module.new do
        extend Fiddle::Importer
        dlload 'libzstd.so.1'
        extern 'size_t ZSTD_compressBound(size_t)'
        extern 'size_t ZSTD_compress(void*, size_t, const void*, size_t, int)'
        extern 'size_t ZSTD_isError(size_t)'
      end
      mod
    end
    src = Fiddle::Pointer[data.to_s.b]
    bound = @api.ZSTD_compressBound(data.bytesize)
    dst = Fiddle::Pointer.malloc(bound)
    written = @api.ZSTD_compress(dst, bound, src, data.bytesize, level)
    raise "zstd compression failed (code #{written})" if @api.ZSTD_isError(written) != 0

    dst.to_str(written)
  end
end

# Minimal ZIP writer (store/deflate) mirroring UnsignedPackageBuilder::ZipWriter:
# Elten reads setups with rubyzip, which accepts these classic structures.
class ZipWriter
  Entry = Struct.new(:name, :crc, :compressed_size, :uncompressed_size, :method,
    :offset, :dos_time, :dos_date, keyword_init: true)

  def initialize(path)
    @io = File.open(path, 'wb')
    @entries = []
  end

  def add(name, data, mtime = Time.now)
    normalized = name.to_s.tr('\\', '/')
    raise "Unsafe setup entry #{name.inspect}" if normalized.empty? || normalized.start_with?('/') || normalized.include?(':') || normalized.split('/').include?('..')

    data = data.to_s.b
    compressed = deflate(data)
    method = 8
    if compressed.bytesize >= data.bytesize
      compressed = data
      method = 0
    end
    dos_time, dos_date = dos_datetime(mtime)
    entry = Entry.new(:name => normalized, :crc => Zlib.crc32(data),
      :compressed_size => compressed.bytesize, :uncompressed_size => data.bytesize,
      :method => method, :offset => @io.pos, :dos_time => dos_time, :dos_date => dos_date)
    name_bytes = normalized.encode(Encoding::UTF_8)
    @io.write([0x04034b50, 20, 0x0800, method, dos_time, dos_date, entry.crc,
      entry.compressed_size, entry.uncompressed_size, name_bytes.bytesize, 0].pack('L<S<S<S<S<S<L<L<L<S<S<'))
    @io.write(name_bytes)
    @io.write(compressed)
    @entries << entry
  end

  def close
    return if @io.nil?

    central_offset = @io.pos
    @entries.each { |entry| write_central_entry(entry) }
    central_size = @io.pos - central_offset
    @io.write([0x06054b50, 0, 0, @entries.size, @entries.size, central_size,
      central_offset, 0].pack('L<S<S<S<S<L<L<S<'))
    @io.close
    @io = nil
  end

  private

  def deflate(data)
    stream = Zlib::Deflate.new(Zlib::BEST_COMPRESSION, -Zlib::MAX_WBITS)
    stream.deflate(data, Zlib::FINISH)
  ensure
    stream.close if stream != nil
  end

  def dos_datetime(time)
    year = [[time.year, 1980].max, 2107].min
    [(time.hour << 11) | (time.min << 5) | (time.sec / 2),
      ((year - 1980) << 9) | (time.month << 5) | time.day]
  end

  def write_central_entry(entry)
    name_bytes = entry.name.encode(Encoding::UTF_8)
    @io.write([0x02014b50, 20, 20, 0x0800, entry.method, entry.dos_time,
      entry.dos_date, entry.crc, entry.compressed_size, entry.uncompressed_size,
      name_bytes.bytesize, 0, 0, 0, 0, 0, entry.offset].pack('L<S<S<S<S<S<S<L<L<L<S<S<S<S<S<L<L<'))
    @io.write(name_bytes)
  end
end

def parse_manifest(source_dir)
  app_file = File.join(source_dir, '__app.rb')
  body = File.read(app_file, :encoding => Encoding::UTF_8)
  block = body[/=begin Elten3AppInfo(.*?)=end Elten3AppInfo/m, 1]
  raise "Elten3AppInfo block not found in #{app_file}" if block.nil?

  JSON.parse(block)
end

def each_source_file(root, &block)
  root_key = File.realpath(root)
  Dir.glob(File.join(root, '**', '*')).sort.each do |file|
    next unless File.file?(file) && !File.symlink?(file)

    resolved = File.realpath(file)
    next unless resolved.start_with?(root_key + File::SEPARATOR)

    relative = file.delete_prefix(root + File::SEPARATOR).tr('\\', '/')
    block.call(file, relative)
  end
end

# .eltenapp code container: MAGIC + zstd(metadata JSON) + zstd-compressed .rb
# records, raw Audio/ sound records and locale records.
def code_container(root, metadata)
  buffer = +''.b
  buffer << MAGIC.b
  compressed_metadata = ZstdCompressor.compress(JSON.generate(metadata))
  buffer << [compressed_metadata.bytesize].pack('L<') << compressed_metadata

  each_source_file(root) do |file, relative|
    ext = File.extname(relative).downcase
    if ext == '.rb'
      write_named_record(buffer, 1, relative, ZstdCompressor.compress(File.binread(file)))
    elsif relative.start_with?('Audio/') && SOUND_EXTENSIONS.include?(ext)
      write_named_record(buffer, 2, relative, File.binread(file))
    elsif relative.start_with?('locale/') && ext == '.mo'
      lang = File.basename(relative, '.mo')[0, 2].to_s.upcase
      next unless lang.match?(/\A[A-Z]{2}\z/)

      content = ZstdCompressor.compress(File.binread(file))
      buffer << [3].pack('C') << lang << [content.bytesize].pack('L<') << content
    end
  end
  buffer
end

def write_named_record(buffer, type, name, content)
  name_bytes = name.encode(Encoding::UTF_8)
  raise "Program file name is too long: #{name}" if name_bytes.bytesize > 0xffff

  buffer << [type, name_bytes.bytesize].pack('CS<') << name_bytes
  buffer << [content.bytesize].pack('L<') << content
end

# .eltsetup: ZIP with __manifest.json (payload metadata + entry) and the
# .eltenapp container as the payload, plus loose non-code resources.
def setup_package(root, output, metadata, code)
  code_name = "#{File.basename(output, '.eltsetup')}.eltenapp"
  setup_manifest = { 'type' => 'application', 'payload' => metadata.merge('entry' => code_name) }
  writer = ZipWriter.new(output)
  writer.add('__manifest.json', JSON.pretty_generate(setup_manifest) + "\n")
  writer.add(code_name, code)
  each_source_file(root) do |file, relative|
    ext = File.extname(relative).downcase
    next if ext == '.rb' || ext == '.eltenapp' || relative == '__manifest.json'
    next if relative.start_with?('Audio/') && SOUND_EXTENSIONS.include?(ext)
    next if relative.start_with?('locale/')

    writer.add(relative, File.binread(file), File.mtime(file))
  end
  writer.close
rescue Exception
  begin
    writer.close if defined?(writer) && writer
  rescue StandardError
    nil
  end
  raise
end

def build(source_dir, output)
  root = File.realpath(source_dir)
  FileUtils.mkdir_p(File.dirname(output))
  metadata = parse_manifest(source_dir)
  raise 'Manifest must not declare gems for the unsigned builder' unless Array(metadata['gems']).empty?

  code = code_container(root, metadata)
  if output.to_s.end_with?('.eltsetup')
    setup_package(root, output, metadata, code)
    format = 'eltsetup'
  else
    File.binwrite(output, code)
    format = 'eltenapp'
  end
  { 'path' => output, 'format' => format, 'size' => File.size(output).to_i, 'signed' => false }
end

root = File.expand_path('..', __dir__)
source = File.join(root, 'src')
output = ARGV[0] || File.join(root, 'build', "#{APP_NAME}.eltenapp")
require 'fileutils'
result = build(source, output)
puts "Built #{result['path']} (#{result['size']} bytes, unsigned, #{result['format']})"
