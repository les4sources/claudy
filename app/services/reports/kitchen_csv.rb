require "csv"

module Reports
  # Export du détail cuisine pour la compta (epic #219, phase 5). Trois choix
  # dictés par Excel en Belgique : séparateur point-virgule, BOM UTF-8 (sans
  # lui, Excel lit les accents de travers), virgule décimale.
  class KitchenCsv
    HEADERS = ["Date", "Moment", "Client", "Type", "Convives", "Prix", "Coût", "Marge",
               "S'en charge", "Statut", "Précisions"].freeze

    BOM = "﻿".freeze

    def initialize(report)
      @report = report
    end

    def to_csv
      BOM + CSV.generate(col_sep: ";") do |csv|
        csv << HEADERS
        @report.lines.each { |line| csv << row(line) }
      end
    end

    private

    def row(line)
      [
        line.date&.iso8601,
        line.moment_label,
        line.stay&.customer&.name,
        line.label,
        line.people,
        euros(line.price_cents),
        line.cost_cents.nil? ? nil : euros(line.cost_cents),
        line.cost_cents.nil? ? nil : euros(line.margin_cents),
        line.responsible_human&.name,
        line.status_label,
        line.notes
      ]
    end

    def euros(cents) = format("%.2f", cents.to_i / 100.0).tr(".", ",")
  end
end
