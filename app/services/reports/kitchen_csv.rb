require "csv"

module Reports
  # Export du détail cuisine pour la compta (epic #219, phase 5). Trois choix
  # dictés par Excel en Belgique : séparateur point-virgule, BOM UTF-8 (sans
  # lui, Excel lit les accents de travers), virgule décimale.
  class KitchenCsv
    HEADERS = ["Date", "Moment", "Client", "Type", "Convives", "Prix",
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
        safe(line.stay&.customer&.name),
        line.label,
        line.people,
        euros(line.price_cents),
        line.responsible_human&.name,
        line.status_label,
        safe(line.notes)
      ]
    end

    def euros(cents) = format("%.2f", cents.to_i / 100.0).tr(".", ",")

    # Excel interprète comme une FORMULE toute cellule qui commence par =, +, -
    # ou @. Le nom du client vient du funnel public : on le neutralise d'une
    # apostrophe, qu'Excel avale sans l'afficher.
    def safe(value)
      text = value.to_s
      text.start_with?("=", "+", "-", "@") ? "'#{text}" : text
    end
  end
end
