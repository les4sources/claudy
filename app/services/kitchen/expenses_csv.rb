require "csv"

module Kitchen
  # Export du détail des dépenses de la cuisine (epic #269, phase 2).
  #
  # Mêmes trois choix que l'export des prestations, dictés par Excel en
  # Belgique : séparateur point-virgule, BOM UTF-8 (sans lui, Excel lit les
  # accents de travers), virgule décimale.
  #
  # Le code du compte et son intitulé occupent DEUX colonnes : c'est le code
  # qu'un tableau croisé regroupe, et l'intitulé qu'un humain lit.
  class ExpensesCsv
    HEADERS = ["Date", "Écriture", "Libellé", "Compte", "Intitulé du compte",
               "Tiers", "Montant"].freeze

    BOM = "﻿".freeze

    def initialize(report)
      @report = report
    end

    def to_csv
      BOM + CSV.generate(col_sep: ";") do |csv|
        csv << HEADERS
        @report.expense_lines.each { |line| csv << row(line) }
      end
    end

    private

    def row(line)
      entry = line.journal_entry
      [
        entry.entry_date&.iso8601,
        entry.reference,
        safe(line.label.presence || entry.label),
        line.general_account.code,
        safe(line.general_account.name),
        safe(line.third_party&.name),
        # Le sens du grand livre : une charge est un débit, une note de crédit
        # ressort en négatif plutôt que de disparaître.
        euros(line.signed_cents)
      ]
    end

    def euros(cents) = format("%.2f", cents.to_i / 100.0).tr(".", ",")

    # Excel interprète comme une FORMULE toute cellule qui commence par =, +, -
    # ou @. Un libellé d'écriture vient de la saisie : on le neutralise d'une
    # apostrophe, qu'Excel avale sans l'afficher.
    def safe(value)
      text = value.to_s
      text.start_with?("=", "+", "-", "@") ? "'#{text}" : text
    end
  end
end
