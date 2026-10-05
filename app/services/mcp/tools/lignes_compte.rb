module Mcp
  module Tools
    class LignesCompte < Base
      tool "lignes_compte",
           title: "Lignes d'un compte",
           description: "Les lignes du grand livre d'un compte, filtrables par poste, type et période, avec leur " \
                        "identifiant (#id), leur montant signé, la référence du règlement et le verrou éventuel. " \
                        "Les identifiants servent aux outils de correction.",
           schema: {
             properties: {
               compte: COMPTE,
               poste: POSTE,
               type: { type: "string", description: "Type de ligne : bar, grocery, meal, batchcooking, cook_fee, " \
                                                    "recurring, settlement, payout, reversal…" },
               du: DATE.merge(description: "Depuis cette date incluse (AAAA-MM-JJ)."),
               au: DATE.merge(description: "Jusqu'à cette date incluse (AAAA-MM-JJ)."),
               signe: { type: "string", enum: %w[debits credits], description: "debits = montants dus, credits = règlements et avoirs." },
               inclure_supprimees: { type: "boolean", description: "Montrer aussi les lignes supprimées (non par défaut)." },
               limite: { type: "integer", description: "Nombre maximum de lignes (300 par défaut)." }
             },
             required: ["compte"]
           }

      def call(arguments)
        compte = compte!(arguments["compte"])
        scope = arguments["inclure_supprimees"] ? AccountEntry.with_deleted { lignes(compte, arguments).to_a } : lignes(compte, arguments).to_a
        return "Aucune ligne pour ces critères sur #{compte.code}." if scope.empty?

        total = scope.reject { |e| e.deleted_at }.sum(&:amount_cents)
        corps = scope.map { |entry| "#{ligne(entry)}#{' [SUPPRIMÉE]' if entry.deleted_at}" }
        "#{compte.code} — #{compte.name} : #{scope.size} ligne(s), total #{euros(total)}\n#{corps.join("\n")}"
      end

      private

      def lignes(compte, arguments)
        limite = (arguments["limite"] || 300).to_i.clamp(1, 2000)
        scope = AccountEntry.where(member_account_id: compte.id).includes(:account_settlement).chronological
        scope = scope.where(flow: poste!(arguments["poste"])) if arguments["poste"].present?
        scope = scope.where(kind: arguments["type"]) if arguments["type"].present?
        debut = date_ou_nil(arguments["du"], "du")
        fin = date_ou_nil(arguments["au"], "au")
        scope = scope.where(entry_date: debut..) if debut
        scope = scope.where(entry_date: ..fin) if fin
        scope = scope.where("amount_cents > 0") if arguments["signe"] == "debits"
        scope = scope.where("amount_cents < 0") if arguments["signe"] == "credits"
        scope.last(limite)
      end
    end
  end
end
