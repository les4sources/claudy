module Mcp
  module Tools
    # La section 4 de `diagnostic.rb` : les virements reçus en banque qui
    # semblent venir de ce compte, et où ils ont été affectés. Un virement
    # « NON AFFECTÉ » est un paiement que le compte n'a pas encore vu.
    class VirementsRecus < Base
      tool "virements_recus",
           title: "Virements reçus d'un compte",
           description: "Les entrées bancaires qui semblent venir d'un compte (IBAN déjà rapproché, code SRC dans la " \
                        "communication, mots du nom du compte ou du ménage, ou mots donnés), avec leur affectation comptable. " \
                        "Sert à retrouver un paiement que le compte ne voit pas.",
           schema: {
             properties: {
               compte: COMPTE,
               depuis: DATE.merge(description: "Depuis cette date (AAAA-MM-JJ). Douze mois par défaut."),
               mots: { type: "array", items: { type: "string" },
                       description: "Mots à chercher dans le nom du donneur d'ordre ou la communication, en plus " \
                                    "de ceux du nom du compte. Préférer les noms de famille aux prénoms." }
             },
             required: ["compte"]
           }

      LIMITE = 200

      def call(arguments)
        compte = compte!(arguments["compte"])
        depuis = date_ou_nil(arguments["depuis"], "depuis") || 12.months.ago.to_date

        noms = [compte.name, compte.household&.name].compact.join(" ")
        mots = (noms.split(/[^[:alpha:]]+/) + Array(arguments["mots"]))
               .map { |mot| I18n.transliterate(mot.to_s).downcase.strip }.select { |mot| mot.size > 3 }.uniq
        ibans = CashAllocation.where(document: compte).joins(:cash_entry).distinct
                              .pluck("cash_entries.counterparty_iban").compact_blank
        filtres = mots.map do |mot|
          CashEntry.sanitize_sql_array(["counterparty_name ILIKE :m OR communication ILIKE :m", { m: "%#{mot}%" }])
        end
        filtres << CashEntry.sanitize_sql_array(["counterparty_iban IN (?)", ibans]) if ibans.any?
        filtres << CashEntry.sanitize_sql_array(["communication ILIKE ?", "%#{compte.code}%"])

        entrees = CashEntry.where("amount_cents > 0").where(entry_date: depuis..).where(filtres.join(" OR "))
                           .includes(cash_allocations: :general_account).order(:entry_date).limit(LIMITE).to_a
        entete = "Virements reçus depuis le #{depuis} pour #{compte.code} — #{compte.name} " \
                 "(mots : #{mots.join(', ').presence || '—'} ; IBAN connus : #{ibans.join(', ').presence || 'aucun'})"
        return "#{entete}\nAucun." if entrees.empty?

        corps = entrees.map do |entree|
          affectations = entree.cash_allocations.map do |a|
            "#{a.general_account&.code} #{euros(a.amount_cents)}#{' → ce compte' if a.document == compte}"
          end
          "##{entree.id}  #{entree.entry_date}  #{euros(entree.amount_cents).rjust(11)}  #{entree.counterparty_name}  " \
            "« #{entree.communication} »\n    #{affectations.any? ? affectations.join(', ') : 'NON AFFECTÉ (encore dans « À affecter »)'}"
        end
        "#{entete}\n#{corps.join("\n")}"
      end
    end
  end
end
