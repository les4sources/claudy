module Mcp
  module Tools
    module Finances
      # Comptabilité > Trésorerie > Règles d'affectation > Accepter en masse
      # (AllocationSuggestionsController#bulk) : un lot BORNÉ, jamais « tout ».
      # La borne est une règle, ou un compte proposé par Jev, au-dessus d'un
      # seuil de confiance. Chaque ligne entièrement affectée est comptabilisée.
      class AccepterSuggestions < Ecriture
        include Commun

        LIMITE = 300
        LIMITE_MAX = 1000
        EXEMPLES = 10

        tool "accepter_suggestions",
             title: "Accepter un lot de suggestions d'affectation",
             description: "Accepte d'un coup les suggestions en attente d'UNE règle (regle), ou celles de Jev pour UN " \
                          "compte (jev_compte), au-dessus d'un seuil de confiance. Jamais toutes règles confondues. " \
                          "Chaque ligne acceptée est affectée et, entièrement couverte, comptabilisée. L'aperçu donne " \
                          "le nombre, le total et des exemples. Les lots se lisent avec regles_affectation.",
             schema: {
               properties: {
                 regle: { type: %w[integer string], description: "La règle (#id ou nom). Ou jev_compte, pas les deux." },
                 jev_compte: COMPTE_GENERAL.merge(description: "Le compte proposé par Jev (701001, « bar »). Ou regle, pas les deux."),
                 seuil: { type: %w[integer string], description: "Confiance minimum, 1 à 100. Défaut : 80 pour une règle, 95 pour Jev." },
                 compte_tresorerie: { type: "string", description: "Seulement les lignes de ce compte (Triodos, Beobank…). Facultatif." },
                 sauf: { type: "array", items: { type: %w[integer string] },
                         description: "Lignes (#id) à laisser hors du lot : leur suggestion reste en attente, à traiter une par une." },
                 limite: { type: %w[integer string], description: "Au plus ce nombre de suggestions par appel (défaut #{LIMITE}, max #{LIMITE_MAX}), les plus sûres d'abord." }
               }
             }

        # Une transaction par suggestion, comme à l'écran : une ligne
        # comptabilisée entre-temps est sautée, elle n'annule pas le lot.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          lot = lot!(arguments)
          limite = (Integer(arguments["limite"].to_s, exception: false) || LIMITE).clamp(1, LIMITE_MAX)
          sauf = Array(arguments["sauf"]).map { |ligne| id!(ligne, "ligne") }
          tout = lot.suggestions.where.not(cash_entry_id: sauf).includes(:general_account, :team, cash_entry: :cash_account).to_a
          raise Error, "Aucune suggestion en attente dans ce lot (#{borne(arguments, lot)})." if tout.empty?

          choisies = tout.first(limite)
          Plan.new(resume: resume(arguments, lot, choisies, tout.size),
                   empreinte: [signature(arguments), choisies.map(&:id).sort],
                   donnees: { arguments: arguments.except("motif", "confirmation"), ids: choisies.map(&:id) })
        end

        def appliquer(plan)
          resultat = metier! { lot!(plan.donnees[:arguments]).run!(ids: plan.donnees[:ids]) }
          texte = "#{resultat.accepted} suggestion(s) acceptée(s)."
          texte += " #{resultat.skipped} sautée(s) (déjà traitées ou exercice manquant)." if resultat.skipped.positive?
          "#{texte} Reste « À affecter » : #{CashEntry.pending.count} ligne(s)."
        end

        def lot!(arguments)
          if arguments["regle"].present? == arguments["jev_compte"].present?
            raise Error, "Donne une règle (regle) ou un compte proposé par Jev (jev_compte), un seul des deux."
          end

          regle = arguments["regle"].present? ? regle!(arguments["regle"]) : nil
          compte = arguments["jev_compte"].present? ? compte_general!(arguments["jev_compte"]) : nil
          seuil = arguments["seuil"].present? ? Integer(arguments["seuil"].to_s, exception: false) : (regle ? 80 : 95)
          raise Error, "seuil : un nombre de 1 à 100." if seuil.nil?

          tresorerie = arguments["compte_tresorerie"].present? ? compte_tresorerie!(arguments["compte_tresorerie"]) : nil
          ::Finance::BulkAcceptSuggestions.new(rule: regle, jev_account: compte, threshold: seuil,
                                               cash_account: tresorerie, whodunnit: whodunnit)
        end

        def borne(arguments, lot)
          quoi = arguments["regle"].present? ? "règle « #{regle!(arguments['regle']).label} »" : "Jev → #{compte_general!(arguments['jev_compte'])}"
          "#{quoi}, #{lot.threshold} % et plus"
        end

        def resume(arguments, lot, choisies, total)
          lignes = ["Accepter #{choisies.size} suggestion(s) : #{borne(arguments, lot)}, " \
                    "#{euros(choisies.sum { |s| s.amount_cents.abs })}."]
          lignes << "#{total - choisies.size} autre(s) restent pour un prochain appel (limite)." if total > choisies.size
          lignes << "Laissées hors du lot : #{Array(arguments['sauf']).size} ligne(s)." if Array(arguments["sauf"]).any?
          comptes = choisies.group_by { |s| [s.general_account.to_s, s.team&.name].compact.join(" · ") }
          comptes.each { |compte, liste| lignes << "  → #{compte} : #{liste.size}" }
          confiances = choisies.map(&:confidence)
          lignes << "Confiance de #{confiances.min} à #{confiances.max} %."
          lignes << "Exemples :"
          choisies.sample(EXEMPLES, random: Random.new(choisies.map(&:id).sum)).each do |s|
            lignes << "  #{ligne_tresorerie(s.cash_entry)} (#{s.confidence} %)"
          end
          lignes << "Chaque ligne entièrement couverte est comptabilisée dans la foulée."
          lignes.join("\n")
        end
      end
    end
  end
end
