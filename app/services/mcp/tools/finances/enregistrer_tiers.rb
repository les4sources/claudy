module Mcp
  module Tools
    module Finances
      # Comptabilité > Tiers (ThirdPartiesController #create, #update,
      # #deactivate et #reactivate). Un tiers ne se supprime pas, il se
      # désactive : des écritures le portent. Son code se dérive du nom.
      class EnregistrerTiers < Ecriture
        include Commun

        TYPES = Tiers::TYPES

        tool "enregistrer_tiers",
             title: "Créer ou corriger un tiers",
             description: "Crée un fournisseur ou un client (le code se dérive du nom), le corrige (nom, type, TVA, " \
                          "IBAN, email, notes, membre rattaché), le désactive ou le réactive (`actif`). Un fournisseur " \
                          "actif qui porte déjà ce numéro de TVA n'est pas recréé : on le signale. Les tiers existants : tiers.",
             schema: {
               properties: {
                 tiers: { type: %w[integer string], description: "Pour corriger : le tiers (#id ou nom). Absent : nouveau tiers." },
                 nom: { type: "string" },
                 type: { type: "string", enum: TYPES.keys, description: "Défaut à la création : fournisseur." },
                 tva: { type: "string", description: "Numéro de TVA (BE0123456789). « aucun » pour l'effacer." },
                 iban: { type: "string", description: "IBAN pour payer ses factures. « aucun » pour l'effacer." },
                 email: { type: "string" },
                 notes: { type: "string" },
                 membre: { type: "string", description: "Le membre du collectif que ce tiers représente (nom), ou « aucun »." },
                 actif: { type: "boolean", description: "false pour désactiver, true pour réactiver." }
               }
             }

        private

        def planifier(arguments)
          tiers = arguments["tiers"].present? ? tiers_existant!(arguments["tiers"]) : nil
          attributs = attributs!(arguments, tiers)
          raise Error, "Rien à changer." if tiers && attributs.empty?

          if tiers.nil? && (jumeau = meme_tva(attributs[:vat_number]))
            raise Error, "Le fournisseur ##{jumeau.id} #{jumeau.name} porte déjà ce numéro de TVA : corrige-le plutôt."
          end

          apres = simuler { ecrire(tiers&.id, attributs) }
          resume = tiers ? "Corriger : #{ligne(tiers)}\nAprès : #{apres}" : "Nouveau tiers : #{apres}"
          Plan.new(resume: resume, empreinte: [tiers && etat_de(tiers), attributs.transform_values(&:to_s).sort],
                   donnees: { id: tiers&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Tiers enregistré : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          tiers = id ? ThirdParty.find(id) : ThirdParty.new(kind: "supplier")
          metier! { tiers.update!(attributs) }
          ligne(tiers.reload)
        end

        def ligne(t)
          ["##{t.id} #{t.name} (#{t.code}, #{t.kind_label.downcase})", ("TVA #{t.vat_number}" if t.vat_number.present?),
           ("IBAN #{t.iban_masked}" if t.iban.present?), t.email.presence, ("membre #{t.human.name}" if t.human),
           ("DÉSACTIVÉ" unless t.active)].compact.join(" · ")
        end

        # Un tiers désactivé reste corrigible et réactivable : on cherche dans tous.
        def tiers_existant!(reference) = par_nom!(ThirdParty.all, reference, "tiers")

        def meme_tva(tva)
          normalisee = MailIntake::InvoiceCandidates.normalize_vat(tva)
          return nil unless normalisee

          ThirdParty.actives.suppliers.find { |t| MailIntake::InvoiceCandidates.normalize_vat(t.vat_number) == normalisee }
        end

        def attributs!(arguments, tiers)
          a = {}
          a[:name] = arguments["nom"].to_s.strip if arguments["nom"].present?
          raise Error, "Donne le nom du tiers." if tiers.nil? && a[:name].blank?

          if arguments["type"].present?
            a[:kind] = TYPES[arguments["type"]] || raise(Error, "type : #{TYPES.keys.join(', ')}.")
          end
          { "tva" => :vat_number, "iban" => :iban }.each do |cle, champ|
            next if arguments[cle].blank?

            a[champ] = arguments[cle].to_s.strip.match?(/\A(aucune?|néant)\z/i) ? nil : arguments[cle].to_s.strip
          end
          a[:email] = arguments["email"].to_s.strip.presence if arguments.key?("email")
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          if arguments["membre"].present?
            a[:human_id] = arguments["membre"].to_s.strip.casecmp?("aucun") ? nil : membre!(arguments["membre"]).id
          end
          a[:active] = arguments["actif"] unless arguments["actif"].nil?
          a
        end
      end
    end
  end
end
