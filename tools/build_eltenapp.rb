# frozen_string_literal: true

# Builds an unsigned .eltenapp from the elten_app folder, mirroring Elten's
# Programs::UnsignedPackageBuilder (src/eapi/unsigned_package_builder.rb).
# Uses zstd-ruby when available, otherwise falls back to the system libzstd
# via Fiddle. Output: build/MileByMile.eltenapp.
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

def parse_manifest(source_dir)
  app_file = File.join(source_dir, '__app.rb')
  body = File.read(app_file, :encoding => Encoding::UTF_8)
  block = body[/=begin Elten3AppInfo(.*?)=end Elten3AppInfo/m, 1]
  raise "Elten3AppInfo block not found in #{app_file}" if block.nil?

  JSON.parse(block)
end

def build(source_dir, output)
  root = File.realpath(source_dir)
  FileUtils.mkdir_p(File.dirname(output))
  metadata = parse_manifest(source_dir)
  raise 'Manifest must not declare gems for the unsigned builder' unless Array(metadata['gems']).empty?

  buffer = +''.b
  buffer << MAGIC.b
  compressed_metadata = ZstdCompressor.compress(JSON.generate(metadata))
  buffer << [compressed_metadata.bytesize].pack('L<') << compressed_metadata

  Dir.glob(File.join(root, '**', '*')).sort.each do |file|
    next unless File.file?(file) && !File.symlink?(file)
    relative = file.delete_prefix(root + File::SEPARATOR).tr('\\', '/')
    ext = File.extname(relative).downcase
    content = File.binread(file)
    if ext == '.rb'
      write_named_record(buffer, 1, relative, ZstdCompressor.compress(content))
    elsif relative.start_with?('Audio/') && SOUND_EXTENSIONS.include?(ext)
      write_named_record(buffer, 2, relative, content)
    elsif relative.start_with?('locale/') && ext == '.mo'
      lang = File.basename(relative, '.mo')[0, 2].upcase
      next unless lang.match?(/\A[A-Z]{2}\z/)

      buffer << [3].pack('C') << lang << [content.bytesize].pack('L<') << content
    end
  end

  File.binwrite(output, buffer)
  { 'path' => output, 'format' => 'eltenapp', 'size' => buffer.bytesize, 'signed' => false }
end

def write_named_record(buffer, type, name, content)
  name_bytes = name.encode(Encoding::UTF_8)
  raise "Program file name is too long: #{name}" if name_bytes.bytesize > 0xffff

  buffer << [type, name_bytes.bytesize].pack('CS<') << name_bytes
  buffer << [content.bytesize].pack('L<') << content
end

root = File.expand_path('..', __dir__)
source = File.join(root, 'elten_app')
output = ARGV[0] || File.join(root, 'build', "#{APP_NAME}.eltenapp")
require 'fileutils'
result = build(source, output)
puts "Built #{result['path']} (#{result['size']} bytes, unsigned)"
