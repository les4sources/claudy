module Mcp
  module Tools
    module Finances
      # Comptabilité > Fournisseurs > Dettes et litiges (LiabilitiesController) :
      # enregistrer ou corriger une dette sans facture — la taxe communale
      # réclamée, un arriéré, une contestation. Le montant retenu (par défaut le
      # haut de la fourchette, sinon le réclamé) sort de la trésorerie à la date
      # probable, ou aujourd'hui sans date.
      class EnregistrerDetteLitige < Ecriture
        include Commun

        NATURES = { "dette" => "debt", "litige" => "dispute", "risque" => "risk" }.freeze
        STATUTS = { "en_cours" => "open", "soldee" => "settled", "abandonnee" => "dropped" }.freeze

        tool "enregistrer_dette_litige",
             title: "Enregistrer une dette ou un litige sans facture",
             description: "Crée ou corrige une dette ou un litige SANS facture encodée (taxe réclamée, arriéré, " \
                          "contestation, risque connu) : montant réclamé, fourchette de ce qu'on paiera, montant " \
                          "retenu, date probable, étalement. Le retenu (défaut : le haut de la fourchette, sinon le " \
                          "réclamé) pèse dans la trésorerie. Pour solder ou abandonner : statut. Rien n'est comptabilisé. " \
                          "Les dettes en cours se lisent avec a_payer.",
             schema: {
               properties: {
                 dette: { type: %w[integer string], description: "Pour corriger : l'identifiant (#3), rendu par a_payer. Absent : nouvelle dette." },
                 libelle: { type: "string", description: "Ex. « Taxe communale d'hébergement 2021-2025 »." },
                 nature: { type: "string", enum: NATURES.keys, description: "dette (montant connu), litige (on conteste) ou risque (pas encore réclamé). Défaut : litige." },
                 entite: ENTITE.merge(description: "Entité qui doit. Défaut : la fondation."),
                 creancier: { type: "string", description: "Le tiers qui réclame (nom). Facultatif." },
                 pole: POLE.merge(description: "Pôle concerné. Facultatif."),
                 reclame: MONTANT.merge(description: "Montant réclamé, en euros."),
                 bas: MONTANT.merge(description: "Bas de la fourchette de ce qu'on paiera, en euros."),
                 haut: MONTANT.merge(description: "Haut de la fourchette, en euros."),
                 retenu: MONTANT.merge(description: "Montant retenu pour la gestion. Défaut : le haut, sinon le réclamé."),
                 deja_paye: MONTANT.merge(description: "Ce qui est déjà payé, en euros."),
                 date_probable: DATE.merge(description: "Date probable du paiement (ou de la première mensualité). Sans date : comptée aujourd'hui."),
                 mensualites: { type: %w[integer string], description: "Nombre de mensualités (1 par défaut)." },
                 statut: { type: "string", enum: STATUTS.keys, description: "en_cours, soldee ou abandonnee." },
                 notes: { type: "string" }
               }
             }

        private

        def planifier(arguments)
          dette = arguments["dette"].present? ? dette!(arguments["dette"]) : nil
          attributs = attributs!(arguments, dette)
          raise Error, "Rien à changer." if dette && attributs.empty?

          apres = simuler { ecrire(dette&.id, attributs) }
          resume = [dette ? "Corriger : #{ligne_dette(dette)}" : "Nouvelle dette", "Après : #{apres}"]
          resume << "Pèse dans la trésorerie de la fondation à sa date probable." if apres.include?("en cours")
          Plan.new(resume: resume.join("\n"), empreinte: [dette&.updated_at&.to_f, signature(attributs)],
                   donnees: { id: dette&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Dette enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          dette = id ? Liability.find(id) : Liability.new
          dette.assign_attributes(attributs)
          if dette.retained_cents.nil?
            dette.retained_cents = Liability.prudent_retained_cents(claimed_cents: dette.claimed_cents, high_cents: dette.high_cents)
          end
          raise Error, "Donne un montant : retenu, haut de la fourchette ou réclamé." if dette.retained_cents.nil?

          metier! { dette.save! }
          ligne_dette(Liability.includes(:legal_entity, :third_party).find(dette.id))
        end

        def signature(attributs) = attributs.transform_values(&:to_s).sort.to_h

        def dette!(reference)
          Liability.find_by(id: id!(reference, "dette")) || raise(Error, "Aucune dette ##{reference.to_s.delete('#')}.")
        end

        def attributs!(arguments, dette)
          a = {}
          a[:label] = arguments["libelle"].to_s.strip if arguments["libelle"].present?
          raise Error, "Donne le libellé." if dette.nil? && a[:label].blank?

          if arguments["nature"].present?
            a[:kind] = NATURES[arguments["nature"]] || raise(Error, "nature : #{NATURES.keys.join(', ')}.")
          elsif dette.nil?
            a[:kind] = "dispute"
          end
          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif dette.nil?
            a[:legal_entity_id] = LegalEntity.actives.find_by(form: "foundation")&.id || raise(Error, "Donne l'entité.")
          end
          a[:third_party_id] = tiers!(arguments["creancier"]).id if arguments["creancier"].present?
          a[:team_id] = pole!(arguments["pole"]).id if arguments["pole"].present?
          { "reclame" => :claimed_cents, "bas" => :low_cents, "haut" => :high_cents,
            "retenu" => :retained_cents, "deja_paye" => :paid_cents }.each do |cle, champ|
            a[champ] = cents!(arguments[cle], cle).abs if arguments[cle].present?
          end
          a[:expected_on] = date!(arguments["date_probable"], "date_probable") if arguments["date_probable"].present?
          if arguments["mensualites"].present?
            a[:installments] = Integer(arguments["mensualites"].to_s, exception: false) ||
                               raise(Error, "mensualites : un nombre entier.")
          end
          if arguments["statut"].present?
            a[:status] = STATUTS[arguments["statut"]] || raise(Error, "statut : #{STATUTS.keys.join(', ')}.")
          end
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          a
        end
      end
    end
  end
end
