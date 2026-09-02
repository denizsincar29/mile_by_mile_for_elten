#!/usr/bin/env ruby
# frozen_string_literal: true

# Компилирует GNU-шный .po в бинарный .mo (gettext). Нужен потому, что в
# окружении нет msgfmt: Elten собирает готовый .mo из src/locale/.
#
# Использование: ruby tools/po2mo.rb <input.po> <output.mo>
# Ломается с ненулевым кодом, если в .po встретилась неподдерживаемая
# конструкция (msgid_plural, msgctxt и т.п.) — чтобы не оставить
# пользователя с молча битым .mo.

def unescape(str)
  str.gsub(/\\(?:([abfnrtv\\"])|x([0-9a-fA-F]{2})|([0-7]{1,3}))/) do
    m = Regexp.last_match
    if m[1]
      { 'a' => 7, 'b' => 8, 'f' => 12, 'n' => 10, 'r' => 13,
        't' => 9, 'v' => 11, '\\' => 92, '"' => 34 }.fetch(m[1]).chr
    elsif m[2]
      m[2].to_i(16).chr
    else
      m[3].to_i(8).chr
    end
  end.force_encoding(Encoding::BINARY)
end

def parse_po(path)
  entries = []
  msgid = nil
  msgstr = nil
  in_msgid = false
  in_msgstr = false

  File.readlines(path, encoding: Encoding::UTF_8).each do |raw|
    line = raw.chomp
    next if line.strip.empty? || line.strip.start_with?('#')

    if (m = line.match(/^msgid\s+"(.*)"$/))
      entries << [msgid, msgstr || ''] if msgid
      msgid = unescape(m[1])
      msgstr = nil
      in_msgid = true
      in_msgstr = false
    elsif (m = line.match(/^msgstr\s+"(.*)"$/))
      msgstr = unescape(m[1])
      in_msgid = false
      in_msgstr = true
    elsif line.strip.start_with?('msgid_plural', 'msgctxt')
      abort "po2mo: #{line.strip.split.first} не поддерживается в #{path}"
    elsif (m = line.match(/^"(.*)"$/)) && in_msgstr
      msgstr += unescape(m[1])
    elsif (m = line.match(/^"(.*)"$/)) && in_msgid
      msgid += unescape(m[1])
    else
      abort "po2mo: неожиданная строка #{line.inspect} в #{path}"
    end
  end
  entries << [msgid, msgstr || ''] if msgid

  # заголовок (пустой msgid) должен быть первым; дубликаты msgid недопустимы
  header = entries.find { |id, _| id.empty? }
  rest = entries.reject { |id, _| id.empty? }
  abort "po2mo: нет заголовка (пустой msgid) в #{path}" unless header
  seen = {}
  rest.each do |id, _|
    abort "po2mo: дублирующий msgid #{id.inspect} в #{path}" if seen[id]
    seen[id] = true
  end
  [header, *rest.sort_by { |id, _| id.b }]
end

def write_mo(entries, path)
  n = entries.size
  originals = entries.map(&:first)
  translations = entries.map(&:last)
  orig_table_off = 28
  trans_table_off = orig_table_off + n * 8
  str_off = trans_table_off + n * 8

  out = +''.b
  out << [0x950412de, 0, n, orig_table_off, trans_table_off, 0, 0].pack('V7')

  offset = str_off
  originals.each do |s|
    bytes = s.b
    out << [bytes.bytesize, offset].pack('V2')
    offset += bytes.bytesize + 1 # Elten's loadmo reads [offset..offset+len] and splits on \0
  end
  translations.each do |s|
    bytes = s.b
    out << [bytes.bytesize, offset].pack('V2')
    offset += bytes.bytesize + 1
  end
  out << originals.map { |s| s.b + "\0".b }.join.b
  out << translations.map { |s| s.b + "\0".b }.join.b
  File.binwrite(path, out)
end

abort 'Использование: ruby tools/po2mo.rb <input.po> <output.mo>' unless ARGV.size == 2

entries = parse_po(ARGV[0])
write_mo(entries, ARGV[1])
puts "po2mo: #{ARGV[1]} — #{entries.size} строк из #{ARGV[0]}"
