module Mcp
  module Tools
    module Finances
      # Encoder ou corriger une note de frais ou de mission
      # (ExpenseReportsController#create et #update). Une note ne se corrige
      # que tant qu'elle est « enregistrée » : passée en traitement, elle porte
      # une écriture.
      class EnregistrerNoteDeFrais < Ecriture
        include Commun

        LIGNE_NOTE = {
          type: "object",
          additionalProperties: false,
          properties: {
            date: DATE.merge(description: "Date de la dépense ou du trajet."),
            libelle: { type: "string" },
            montant: MONTANT.merge(description: "Note de frais : le montant payé. Ignoré pour une note de mission."),
            km: { type: %w[number string], description: "Note de mission : les kilomètres (le montant suit le barème du jour)." },
            compte: COMPTE_GENERAL.merge(description: "Compte de charge. Défaut d'une note de mission : déplacements (617000)."),
            pole: POLE,
            fournisseur: { type: "string", description: "Le commerce ou le fournisseur." },
            piece: { type: "string", enum: ExpenseLine::DOC_KINDS, description: "ticket ou invoice." }
          },
          required: %w[date libelle]
        }.freeze

        tool "enregistrer_note_de_frais",
             title: "Encoder ou corriger une note de frais",
             description: "Crée une note de frais (achats avancés par un membre) ou de mission (kilomètres), ou corrige " \
                          "une note encore « enregistrée ». Les lignes données en correction REMPLACENT toutes les " \
                          "lignes. Les justificatifs (photos, PDF) se déposent dans Claudy. Ensuite : geste_note_de_frais traiter.",
             schema: {
               properties: {
                 note: NOTE.merge(description: "Pour corriger : la note. Absente : nouvelle note."),
                 type: { type: "string", enum: ExpenseReport::KINDS, description: "expenses (frais, défaut) ou mileage (mission)." },
                 membre: { type: "string", description: "Qui a avancé l'argent ou roulé (nom, ou « moi »)." },
                 entite: ENTITE.merge(description: "Entité qui rembourse. Défaut : Fondation Les 4 Sources."),
                 deposee_le: DATE.merge(description: "Date de dépôt. Défaut : aujourd'hui."),
                 notes: { type: "string" },
                 lignes: { type: "array", items: LIGNE_NOTE }
               }
             }

        private

        def planifier(arguments)
          note = arguments["note"].present? ? note!(arguments["note"]) : nil
          raise Error, "Cette note est #{note.status_label.downcase} : elle n'est plus modifiable." if note && !note.editable?

          attributs = attributs!(arguments, note)
          raise Error, "Rien à changer." if note && attributs.empty?

          apres = simuler { ecrire(note&.id, attributs) }
          resume = [note ? "Corriger #{ligne_note(note)}" : "Nouvelle note (enregistrée)", "Après : #{apres}"]
          resume << "Les justificatifs se déposent dans Claudy."
          Plan.new(resume: resume.join("\n"), empreinte: [note && etat_de(note), signature(arguments)],
                   donnees: { id: note&.id, attributs: attributs })
        end

        def appliquer(plan)
          "Note enregistrée : #{ecrire(plan.donnees[:id], plan.donnees[:attributs])}"
        end

        def ecrire(id, attributs)
          note = id ? ExpenseReport.find(id) : ExpenseReport.new(created_by: user)
          note.assign_attributes(attributs.except(:lignes))
          if attributs[:lignes]
            existantes = note.expense_lines.map { |l| { id: l.id, _destroy: "1" } }
            note.expense_lines_attributes = existantes + attributs[:lignes].each_with_index.map { |l, i| l.merge(position: i) }
          end
          metier! { note.save! }
          note = ExpenseReport.find(note.id)
          lignes = note.expense_lines.map do |l|
            "\n  #{l.spent_on} #{l.label} : #{euros(l.amount_cents)}#{" (#{format('%g', l.distance_km)} km)" if l.distance_km} → " \
              "#{l.general_account&.code}#{" · pôle #{l.team.name}" if l.team}"
          end
          "#{ligne_note(note)}#{lignes.join}"
        end

        def attributs!(arguments, note)
          a = {}
          kind = arguments["type"].presence
          raise Error, "type : #{ExpenseReport::KINDS.join(', ')}." if kind && !ExpenseReport::KINDS.include?(kind)

          a[:kind] = kind if kind
          a[:kind] ||= "expenses" if note.nil?
          a[:human_id] = membre!(arguments["membre"]).id if arguments["membre"].present?
          raise Error, "Donne le membre qui a avancé l'argent." if note.nil? && a[:human_id].nil?

          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif note.nil?
            entite = LegalEntity.find_by(name: "Fondation Les 4 Sources") || LegalEntity.actives.ordered.first
            a[:legal_entity_id] = entite&.id || raise(Error, "Aucune entité juridique active.")
          end
          a[:submitted_on] = date!(arguments["deposee_le"], "deposee_le") if arguments["deposee_le"].present?
          a[:submitted_on] ||= Date.current if note.nil?
          a[:notes] = arguments["notes"].to_s.strip.presence if arguments.key?("notes")
          mission = (a[:kind] || note&.kind) == "mileage"
          a[:lignes] = lignes!(arguments["lignes"], mission) if arguments.key?("lignes")
          raise Error, "Donne au moins une ligne." if note.nil? && a[:lignes].blank?

          a
        end

        def lignes!(lignes, mission)
          Array(lignes).each_with_index.map do |ligne, index|
            ligne = ligne.to_h
            quoi = "ligne #{index + 1}"
            compte = if ligne["compte"].present?
                       compte_general!(ligne["compte"])
                     elsif mission
                       GeneralAccount.find_by(code: GeneralAccount::TRAVEL_CODE) || raise(Error, "#{quoi} : donne le compte de charge.")
                     else
                       raise Error, "#{quoi} : donne le compte de charge (referentiel_comptable comptes, classe 6)."
                     end
            attributs = {
              spent_on: date!(ligne["date"], "#{quoi} date"), label: ligne["libelle"].to_s.strip,
              general_account_id: compte.id, team_id: ligne["pole"].present? ? pole!(ligne["pole"]).id : nil,
              supplier_name: ligne["fournisseur"].to_s.strip.presence, doc_kind: ligne["piece"].presence
            }
            if mission
              raise Error, "#{quoi} : donne les kilomètres." if ligne["km"].blank?

              km = ligne["km"].to_s.tr(",", ".")
              raise Error, "#{quoi} : kilomètres illisibles « #{ligne['km']} »." unless km.match?(/\A\d+(\.\d+)?\z/)

              attributs[:distance_km] = km.to_f
            else
              attributs[:amount_cents] = cents!(ligne["montant"], "#{quoi} montant").abs
            end
            attributs
          end
        end
      end
    end
  end
end
