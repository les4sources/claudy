module Mcp
  module Tools
    module Finances
      # Comptabilité > Banque & caisse > Coût d'encaissement
      # (CollectionCostController#index) : ce que coûte le fait d'être payé, et
      # les justificatifs mensuels des frais Stripe face à ce que Claudy a compté.
      class CoutEncaissement < Base
        include Commun

        tool "cout_encaissement",
             title: "Coût d'encaissement",
             description: "Sur une période : la commission Stripe par compte (brut, frais, net, taux), le taux global, " \
                          "ce qui est entré par virement sans frais, puis mois par mois les frais comptés par Claudy face " \
                          "au justificatif de Stripe (montant déclaré, écart, PDF déposé ou non). Déclarer un " \
                          "justificatif : justificatif_stripe.",
             schema: {
               properties: {
                 du: DATE.merge(description: "Début. Défaut : le 1er janvier."),
                 au: DATE.merge(description: "Fin. Défaut : le 31 décembre.")
               }
             }

        def call(arguments)
          du = date_ou_nil(arguments["du"], "du") || Date.current.beginning_of_year
          au = date_ou_nil(arguments["au"], "au") || Date.current.end_of_year
          cout = ::Finance::CollectionCost.new(from: du, to: au)

          comptes = cout.rows.map do |r|
            "  #{r[:label]} (#{r[:basis] == :payout ? 'par versement' : 'par transaction'}) : brut #{euros(r[:gross_cents])}, " \
              "frais #{euros(r[:fees_cents])}, net #{euros(r[:net_cents])}, #{taux(r[:rate])}, #{r[:payouts]} versement(s)"
          end
          mois = cout.fee_months.map do |r|
            declare = r.declared_fee_cents.nil? ? "aucun justificatif" : "déclaré #{euros(r.declared_fee_cents)}"
            ecart = r.gap? ? " · ÉCART #{'+' if r.gap_cents.positive?}#{euros(r.gap_cents)}" : ""
            "  #{nom_mois(r.month)} · #{r.label} : compté #{euros(r.counted_fee_cents)} · #{declare}#{ecart}" \
              "#{' · PDF déposé' if r.document?}#{" · réf. #{r.invoice.reference}" if r.invoice&.reference.present?}"
          end

          [
            "Du #{du} au #{au} : frais #{euros(cout.total_fees_cents)} sur #{euros(cout.total_gross_cents)} encaissés par Stripe (#{taux(cout.global_rate)}).",
            "Entré par virement bancaire, sans frais : #{euros(cout.transfer_cents)}.",
            (comptes.any? ? "Par compte :\n#{comptes.join("\n")}" : "Aucun encaissement Stripe sur la période."),
            ("Justificatifs mensuels :\n#{mois.join("\n")}" if mois.any?)
          ].compact.join("\n")
        end

        private

        def taux(valeur) = valeur ? "#{format('%.2f', valeur).tr('.', ',')} %" : "taux —"
      end
    end
  end
end
