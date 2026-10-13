require "zip"
require "nokogiri"
require "bigdecimal"
require "stringio"

module Xlsx
  class ReadError < StandardError; end

  # Un lecteur de classeur Excel (.xlsx) réduit à ce qu'un relevé bancaire
  # demande : les feuilles, leurs lignes, le texte et les nombres des cellules.
  #
  # Pas de gem dédiée : un .xlsx n'est qu'une archive zip de XML, et `rubyzip`
  # et `nokogiri` sont déjà là. Le lecteur ne connaît ni les styles ni les
  # formats, donc pas les dates : une date Excel sort comme le nombre de jours
  # qu'elle est, et c'est l'appelant, qui sait quelle colonne porte une date,
  # qui la convertit (`Xlsx::Reader.date`).
  #
  # Les nombres sortent en `BigDecimal`, jamais en flottant : `-4.83` lu en
  # flottant donne -482,99999 centimes, et un centime perdu sur un relevé est
  # un écart qu'on cherchera des heures.
  class Reader
    # `rows` : { numéro de ligne => [valeur de A, valeur de B, …] }, lignes vides omises.
    Sheet = Struct.new(:name, :hidden, :rows, keyword_init: true)

    MAIN_NS = "http://schemas.openxmlformats.org/spreadsheetml/2006/main".freeze
    REL_NS = "http://schemas.openxmlformats.org/officeDocument/2006/relationships".freeze
    # Un relevé bancaire pèse quelques centaines de kilo-octets. Au-delà, ce
    # n'est pas un relevé, et une archive qui se décompresse en gigaoctets ne
    # doit pas mettre le serveur à genoux.
    MAX_ENTRY_BYTES = 50 * 1024 * 1024

    def self.call(content) = new(content).sheets

    # Le calendrier 1900 d'Excel, tel que tout le monde l'utilise : le jour 1
    # est le 1er janvier 1900, et Excel compte un 29 février 1900 qui n'a pas
    # existé, d'où l'origine au 30 décembre 1899.
    def self.date(value)
      return value if value.is_a?(Date)
      return nil if value.nil? || (value.respond_to?(:empty?) && value.empty?)
      return Date.new(1899, 12, 30) + value.to_i if value.is_a?(Numeric)

      Date.strptime(value.to_s.strip, "%d/%m/%Y")
    rescue Date::Error
      nil
    end

    def initialize(content)
      @content = content.to_s.b
    end

    def sheets
      raise ReadError, "Ce fichier n'est pas un classeur Excel (.xlsx)." unless @content.start_with?("PK")

      # `open_buffer` rend l'archive, pas la valeur du bloc.
      sheets = nil
      Zip::File.open_buffer(StringIO.new(@content)) do |zip|
        @zip = zip
        strings = shared_strings
        sheets = workbook_sheets.map do |name, path, hidden|
          Sheet.new(name: name, hidden: hidden, rows: read_rows(path, strings))
        end
      end
      sheets
    rescue Zip::Error => e
      raise ReadError, "Le classeur Excel est illisible : #{e.message}"
    end

    private

    def xml(path)
      entry = @zip.find_entry(path)
      return nil if entry.nil?
      raise ReadError, "Le classeur Excel est anormalement gros." if entry.size > MAX_ENTRY_BYTES

      Nokogiri::XML(entry.get_input_stream.read)
    end

    # Feuilles dans l'ordre du classeur, avec le fichier XML qui porte chacune.
    def workbook_sheets
      workbook = xml("xl/workbook.xml") or raise ReadError, "Le classeur Excel n'a pas de feuille."
      rels = xml("xl/_rels/workbook.xml.rels")
      targets = rels ? rels.css("Relationship").to_h { |rel| [rel["Id"], rel["Target"]] } : {}

      workbook.xpath("//m:sheets/m:sheet", "m" => MAIN_NS).filter_map do |sheet|
        target = targets[sheet.attribute_with_ns("id", REL_NS)&.value]
        next if target.nil?

        path = target.start_with?("/") ? target.delete_prefix("/") : "xl/#{target}"
        [sheet["name"], path, sheet["state"].present? && sheet["state"] != "visible"]
      end
    end

    def shared_strings
      doc = xml("xl/sharedStrings.xml")
      return [] if doc.nil?

      doc.xpath("//m:si", "m" => MAIN_NS).map { |si| si.xpath(".//m:t", "m" => MAIN_NS).map(&:text).join }
    end

    def read_rows(path, strings)
      doc = xml(path)
      return {} if doc.nil?

      doc.xpath("//m:sheetData/m:row", "m" => MAIN_NS).each_with_object({}) do |row, rows|
        cells = []
        row.xpath("m:c", "m" => MAIN_NS).each do |cell|
          value = cell_value(cell, strings)
          next if value.nil?

          cells[column_index(cell["r"])] = value
        end
        rows[row["r"].to_i] = cells if cells.any?
      end
    end

    def cell_value(cell, strings)
      raw = cell.at_xpath("m:v", "m" => MAIN_NS)&.text

      case cell["t"]
      when "s" then raw && strings[raw.to_i]
      when "inlineStr" then cell.xpath(".//m:is//m:t", "m" => MAIN_NS).map(&:text).join
      when "str" then raw
      when "b" then raw == "1"
      when "e" then nil
      else raw.nil? || raw.empty? ? nil : BigDecimal(raw)
      end
    rescue ArgumentError
      raw
    end

    # « AB12 » → 27 : la colonne, comptée à partir de zéro.
    def column_index(reference)
      letters = reference.to_s[/\A[A-Z]+/]
      raise ReadError, "Référence de cellule illisible : #{reference.inspect}." if letters.nil?

      letters.each_char.reduce(0) { |index, char| (index * 26) + (char.ord - 64) } - 1
    end
  end
end
