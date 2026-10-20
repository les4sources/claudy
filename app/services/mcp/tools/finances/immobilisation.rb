module Mcp
  module Tools
    module Finances
      # Comptabilité › États › Immobilisations (Finance::FixedAssetsController
      # #create et #update) : inscrire un bien au registre ou le corriger.
      class Immobilisation < Ecriture
        include Commun

        tool "immobilisation",
             title: "Inscrire ou corriger une immobilisation",
             description: "Un bien durable au registre des immobilisations : désignation, entité, date d'acquisition, " \
                          "valeur, durée d'utilisation (années), déjà amorti avant Claudy, compte d'immobilisation " \
                          "(classe 2, ex. 240000), compte d'amortissements (classe 2, ex. 240001), compte de dotation " \
                          "(défaut 630100), pôle, date de sortie. Rien n'est comptabilisé : l'achat est déjà au grand " \
                          "livre ; les dotations se passent avec amortissements. Le registre : immobilisations.",
             schema: {
               properties: {
                 bien: { type: %w[integer string], description: "Pour corriger : l'identifiant (#3), rendu par immobilisations. Absent : nouveau bien." },
                 nom: { type: "string" },
                 entite: ENTITE.merge(description: "Entité propriétaire. Défaut : la fondation."),
                 acquis_le: DATE,
                 valeur: MONTANT.merge(description: "Valeur d'acquisition, en euros."),
                 duree: { type: %w[integer string], description: "Durée d'utilisation, en années." },
                 deja_amorti: MONTANT.merge(description: "Amortissements déjà actés avant Claudy, en euros. Défaut : 0."),
                 compte: COMPTE_GENERAL.merge(description: "Compte d'immobilisation (classe 2), ex. 240000."),
                 compte_amortissements: COMPTE_GENERAL.merge(description: "Compte d'amortissements actés (classe 2), ex. 240001."),
                 compte_dotation: COMPTE_GENERAL.merge(description: "Compte de dotation (classe 6). Défaut : 630100."),
                 pole: POLE,
                 sorti_le: DATE.merge(description: "Date de sortie (vendu, cassé, donné) : plus de dotation après."),
                 notes: { type: "string" }
               }
             }

        private

        def planifier(arguments)
          bien = arguments["bien"].present? ? bien!(arguments["bien"]) : nil
          attributs = attributs!(arguments, bien)
          raise Error, "Rien à changer." if bien && attributs.empty?

          apres = simuler { ecrire(bien&.id, attributs) }
          resume = [bien ? "Corriger : ##{bien.id} #{bien.name}" : "Nouvelle immobilisation", "Après : #{apres}"]
          Plan.new(resume: resume.join("\n"), empreinte: [bien && etat_de(bien), attributs.transform_values(&:to_s).sort],
                   donnees: { id: bien&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Immobilisation enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          bien = id ? FixedAsset.find(id) : FixedAsset.new
          bien.assign_attributes(attributs)
          metier! { bien.save! }
          bien.reload
          "##{bien.id} #{bien.name} · #{bien.legal_entity.name} · acquis le #{bien.acquired_on} · valeur #{euros(bien.acquisition_cents)} · " \
            "#{bien.useful_life_years} ans · #{bien.general_account.code} / #{bien.depreciation_account.code} / #{bien.expense_account.code} · " \
            "valeur nette #{euros(bien.net_book_value_cents)}"
        end

        def bien!(reference)
          FixedAsset.find_by(id: id!(reference, "immobilisation")) || raise(Error, "Aucune immobilisation ##{reference.to_s.delete('#')}.")
        end

        def attributs!(arguments, bien)
          a = {}
          a[:name] = arguments["nom"].to_s.strip if arguments["nom"].present?
          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif bien.nil?
            a[:legal_entity_id] = LegalEntity.actives.find_by(form: "foundation")&.id || raise(Error, "Donne l'entité.")
          end
          a[:acquired_on] = date!(arguments["acquis_le"], "acquis_le") if arguments["acquis_le"].present?
          a[:acquisition_cents] = cents!(arguments["valeur"], "valeur").abs if arguments["valeur"].present?
          if arguments["duree"].present?
            a[:useful_life_years] = Integer(arguments["duree"].to_s, exception: false) || raise(Error, "duree : un nombre d'années.")
          end
          a[:prior_depreciation_cents] = cents_ou_zero(arguments["deja_amorti"]) if arguments.key?("deja_amorti")
          a[:general_account_id] = compte_general!(arguments["compte"]).id if arguments["compte"].present?
          a[:depreciation_account_id] = compte_general!(arguments["compte_amortissements"]).id if arguments["compte_amortissements"].present?
          if arguments["compte_dotation"].present?
            a[:expense_account_id] = compte_general!(arguments["compte_dotation"]).id
          elsif bien.nil?
            a[:expense_account_id] = GeneralAccount.find_by(code: FixedAsset::DEFAULT_EXPENSE_CODE)&.id
          end
          a[:team_id] = pole!(arguments["pole"]).id if arguments["pole"].present?
          a[:disposed_on] = date_ou_nil(arguments["sorti_le"], "sorti_le") if arguments.key?("sorti_le")
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          a
        end

        def cents_ou_zero(valeur)
          return 0 if valeur.blank? || valeur.to_s.strip.match?(/\A0+([.,]0+)?\z/)

          cents!(valeur, "deja_amorti").abs
        end
      end
    end
  end
end
