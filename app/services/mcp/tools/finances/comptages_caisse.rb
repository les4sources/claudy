module Mcp
  module Tools
    module Finances
      # Comptabilité > Caisse > Comptages (CashCountsController#index) : les
      # comptages passés et ce que la caisse devrait contenir aujourd'hui.
      class ComptagesCaisse < Base
        include Commun

        LIMITE = 20

        tool "comptages_caisse",
             title: "Comptages de caisse",
             description: "Ce que la caisse devrait contenir aujourd'hui selon la comptabilité, puis les comptages " \
                          "passés (#id, date, compté, attendu, écart, issue, brouillon ou validé). Un brouillon est un " \
                          "écart parti à la recherche de son origine : il se reprend avec compter_caisse.",
             schema: {
               properties: {
                 caisse: { type: "string", description: "La caisse, s'il y en a plusieurs." }
               }
             }

        def call(arguments)
          caisse = caisse!(arguments["caisse"])
          attendu = ::Finance::CashSheet.accounting_balance(cash_account: caisse, up_to: Date.current)
          comptages = CashCount.where(cash_account: caisse).ordered.includes(:counted_by).limit(LIMITE).to_a
          [
            "#{caisse.name} : #{euros(attendu)} attendus aujourd'hui selon la comptabilité.",
            comptages.empty? ? "Aucun comptage." : comptages.map { |c| ligne_comptage(c) }.join("\n")
          ].join("\n")
        end

        private

        def ligne_comptage(comptage)
          ecart = comptage.difference_cents.to_i
          "##{comptage.id}  #{comptage.counted_on}  compté #{euros(comptage.counted_cents)} · attendu #{euros(comptage.expected_cents)} · " \
            "#{ecart.zero? ? 'juste' : "écart #{'+' if ecart.positive?}#{euros(ecart)}"} · " \
            "#{comptage.draft? ? 'BROUILLON' : 'validé'}#{" · #{comptage.resolution_label}" if comptage.resolution}" \
            "#{" · « #{comptage.comment.squish.truncate(80)} »" if comptage.comment.present?}" \
            "#{" · par #{comptage.counted_by.email}" if comptage.counted_by}"
        end
      end
    end
  end
end
