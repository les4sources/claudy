module Mcp
  module Tools
    module Finances
      # Comptabilité > Caisse > Motifs (CashMotifsController) : le vocabulaire
      # de la feuille de caisse et son affectation comptable. Un motif ne se
      # supprime pas, il se désactive : des lignes passées le portent.
      class MotifCaisse < Ecriture
        include Commun

        GESTES = {
          "creer" => "nouveau motif (libelle, sens, compte, entite ; pole facultatif)",
          "modifier" => "changer libellé, sens, compte, pôle ou entité (les lignes déjà saisies gardent leur affectation)",
          "monter" => "le remonter d'un cran dans la liste de saisie",
          "descendre" => "le descendre d'un cran",
          "desactiver" => "le retirer de la liste de saisie",
          "reactiver" => "le remettre dans la liste"
        }.freeze
        SENS = { "entree" => "in", "sortie" => "out", "les_deux" => "both" }.freeze

        tool "motif_caisse",
             title: "Motif de la feuille de caisse",
             description: "Gère les motifs de caisse (vente bar, dépôt banque…) : #{GESTES.map { |cle, sens| "#{cle} (#{sens})" }.join(' ; ')}. " \
                          "Le motif décide du sens d'une ligne de caisse et de son compte. Les motifs existants, dans " \
                          "l'ordre de la liste : referentiel_comptable motifs_caisse.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES.keys },
                 motif_caisse: { type: "string", description: "Sauf pour creer : le motif (libellé ou #id)." },
                 libelle: { type: "string" },
                 sens: { type: "string", enum: SENS.keys, description: "entree, sortie ou les_deux (le montant saisi tranche)." },
                 compte: COMPTE_GENERAL,
                 pole: { type: "string", description: "Pôle (nom). « aucun » pour le retirer." },
                 entite: ENTITE.merge(description: "Entité juridique. Défaut à la création : la première active.")
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)

          motif = geste == "creer" ? nil : motif!(arguments["motif_caisse"])
          case geste
          when "creer", "modifier"
            attributs = attributs!(arguments, motif)
            raise Error, "Rien à changer." if motif && attributs.empty?

            apres = simuler { ecrire(motif&.id, attributs) }
            resume = motif ? "Modifier : #{ligne_motif(motif)}\nAprès : #{apres}" : "Nouveau motif : #{apres}"
            Plan.new(resume: resume, empreinte: [motif && etat_de(motif), attributs.transform_values(&:to_s).sort],
                     donnees: { geste: geste, id: motif&.id, attributs: attributs })
          when "monter", "descendre"
            voisin = motif.neighbour(geste == "monter" ? "up" : "down")
            raise Error, "#{motif.label} est déjà en #{geste == 'monter' ? 'tête' : 'fin'} de liste." if voisin.nil?

            Plan.new(resume: "#{ligne_motif(motif)}\nÉchange sa place avec « #{voisin.label} ».",
                     empreinte: [etat_de(motif), etat_de(voisin)], donnees: { geste: geste, id: motif.id })
          else
            actif = geste == "reactiver"
            raise Error, "#{motif.label} est déjà #{actif ? 'actif' : 'désactivé'}." if motif.active == actif

            Plan.new(resume: "#{ligne_motif(motif)}\n#{actif ? 'Revient dans' : 'Sort de'} la liste de saisie de la caisse.",
                     empreinte: [etat_de(motif)], donnees: { geste: geste, id: motif.id })
          end
        end

        def appliquer(plan)
          d = plan.donnees
          case d[:geste]
          when "creer", "modifier" then "Motif enregistré : #{ecrire(d[:id], d[:attributs])}"
          when "monter", "descendre"
            motif = CashMotif.find(d[:id])
            motif.move!(d[:geste] == "monter" ? "up" : "down")
            "Ordre changé : #{ligne_motif(motif.reload)}"
          else
            motif = CashMotif.find(d[:id])
            metier! { motif.update!(active: d[:geste] == "reactiver") }
            "#{ligne_motif(motif)}"
          end
        end

        def ecrire(id, attributs)
          motif = id ? CashMotif.find(id) : CashMotif.new(position: CashMotif.next_position)
          metier! { motif.update!(attributs) }
          ligne_motif(motif.reload)
        end

        def ligne_motif(motif)
          "« #{motif.label} » (##{motif.id || 'nouveau'}, #{motif.direction_label.to_s.downcase}, position #{motif.position}) → " \
            "#{motif.general_account}#{" · pôle #{motif.team.name}" if motif.team} · #{motif.legal_entity&.name}" \
            "#{' · DÉSACTIVÉ' unless motif.active}"
        end

        def motif!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          raise Error, "Précise le motif (libellé ou #id)." if texte.empty?
          return CashMotif.find_by(id: texte) || raise(Error, "Aucun motif de caisse ##{texte}.") if texte.match?(/\A\d+\z/)

          trouves = CashMotif.where("label ILIKE ?", "%#{CashMotif.sanitize_sql_like(texte)}%").to_a
          exact = trouves.find { |m| m.label.casecmp?(texte) }
          return exact if exact
          return trouves.first if trouves.one?
          raise Error, "Aucun motif de caisse ne correspond à « #{texte} »." if trouves.empty?

          raise Error, "Plusieurs motifs correspondent à « #{texte} » : #{trouves.map(&:label).join(', ')}."
        end

        def attributs!(arguments, motif)
          a = {}
          a[:label] = arguments["libelle"].to_s.strip if arguments["libelle"].present?
          if arguments["sens"].present?
            a[:direction] = SENS[arguments["sens"]] || raise(Error, "sens : #{SENS.keys.join(', ')}.")
          end
          a[:general_account_id] = compte_general!(arguments["compte"]).id if arguments["compte"].present?
          if arguments["pole"].present?
            a[:team_id] = arguments["pole"].to_s.strip.casecmp?("aucun") ? nil : pole!(arguments["pole"]).id
          end
          if arguments["entite"].present?
            a[:legal_entity_id] = entite!(arguments["entite"]).id
          elsif motif.nil?
            a[:legal_entity_id] = LegalEntity.actives.ordered.first&.id
          end
          if motif.nil?
            manquants = { label: "libelle", direction: "sens", general_account_id: "compte" }.reject { |champ, _| a[champ].present? }
            raise Error, "Pour créer un motif, donne : #{manquants.values.join(', ')}." if manquants.any?
          end
          a
        end
      end
    end
  end
end
