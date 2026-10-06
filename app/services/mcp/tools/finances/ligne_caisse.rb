module Mcp
  module Tools
    module Finances
      # La feuille de caisse (CashSheetController) : saisir une ligne
      # d'espèces, la corriger, la retirer. Le MOTIF affecte la ligne et en
      # donne le sens ; la ligne se comptabilise aussitôt.
      class LigneCaisse < Ecriture
        include Commun

        GESTES = %w[ajouter corriger retirer].freeze

        tool "ligne_caisse",
             title: "Ligne de la feuille de caisse",
             description: "Saisit une entrée ou une sortie d'espèces sur la feuille de caisse (motif, date, libellé, " \
                          "montant ; le motif décide du sens et du compte, la ligne est comptabilisée), la corrige " \
                          "(son écriture est contre-passée et repassée), ou la retire avec un motif. Un mois arrêté " \
                          "ne se touche plus. Les motifs : referentiel_comptable motifs_caisse.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES },
                 ligne: LIGNE.merge(description: "Pour corriger ou retirer : la ligne (#id de feuille_de_caisse)."),
                 motif_caisse: { type: "string", description: "Le motif de caisse (libellé ou #id) : vente bar, dépôt banque…" },
                 date: DATE.merge(description: "Défaut : aujourd'hui (ajouter) ou la date actuelle de la ligne (corriger)."),
                 libelle: { type: "string" },
                 montant: MONTANT.merge(description: "En euros, sans signe : le motif donne le sens (sauf motif « les deux » : " \
                                                     "négatif = sortie)."),
                 notes: { type: "string" },
                 caisse: { type: "string", description: "Pour ajouter : la caisse, s'il y en a plusieurs." }
               },
               required: %w[geste]
             }

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.join(', ')}." unless GESTES.include?(geste)
          return plan_retrait(arguments) if geste == "retirer"

          entry = geste == "corriger" ? ligne_de_caisse!(arguments["ligne"]) : nil
          caisse = entry&.cash_account || caisse!(arguments["caisse"])
          motif = if arguments["motif_caisse"].present?
                    motif_caisse!(arguments["motif_caisse"])
                  else
                    entry&.cash_motif || raise(Error, "Donne le motif de caisse : c'est lui qui affecte la ligne.")
                  end
          date = date_ou_nil(arguments["date"], "date") || entry&.entry_date || Date.current
          libelle = arguments["libelle"].to_s.strip.presence || entry&.label || raise(Error, "Donne le libellé de la ligne.")
          montant = arguments["montant"].present? ? cents!(arguments["montant"], "montant") : entry&.amount_cents
          raise Error, "Donne le montant." if montant.nil?

          signe = motif.signed_cents(montant)
          notes = arguments.key?("notes") ? arguments["notes"].to_s.strip.presence : entry&.notes
          [date, entry&.entry_date].compact.each do |jour|
            raise Error, "#{nom_mois(jour.beginning_of_month)} est arrêté : la feuille ne se modifie plus." if MonthClosing.closed?(jour)
          end

          donnees = { geste: geste, id: entry&.id, caisse: caisse.id, motif: motif.id, date: date.iso8601, libelle: libelle,
                      montant: montant, notes: notes }
          resume = [entry ? "Corriger #{ligne_tresorerie(entry)}" : "Nouvelle ligne de caisse (#{caisse.name})"]
          resume << "#{date} · #{motif.label} → #{motif.general_account} · #{libelle} · #{euros(signe)}#{" · #{notes}" if notes}"
          resume << "La ligne est comptabilisée#{' (ancienne écriture contre-passée)' if entry&.posted?}."
          Plan.new(resume: resume.join("\n"), empreinte: [entry && etat_de(entry), signature(arguments)], donnees: donnees)
        end

        def appliquer(plan)
          d = plan.donnees
          motif = d[:geste] == "retirer" ? nil : CashMotif.find(d[:motif])
          metier! do
            if d[:geste] == "corriger"
              entry = ::Finance::UpdateCashLine.new(cash_entry: CashEntry.find(d[:id]), whodunnit: whodunnit)
                                               .update!(motif: motif, entry_date: Date.iso8601(d[:date]), label: d[:libelle],
                                                        amount_cents: d[:montant], notes: d[:notes])
              "Ligne corrigée : #{ligne_tresorerie(entry)}"
            elsif d[:geste] == "retirer"
              ::Finance::UpdateCashLine.new(cash_entry: CashEntry.find(d[:id]), whodunnit: whodunnit).exclude!(@motif)
              "Ligne ##{d[:id]} retirée de la feuille, avec son motif."
            else
              entry = ::Finance::RecordCashLine.new(cash_account: CashAccount.find(d[:caisse]), motif: motif, entry_date: Date.iso8601(d[:date]),
                                                    label: d[:libelle], amount_cents: d[:montant], notes: d[:notes], whodunnit: whodunnit).run!
              "Ligne enregistrée : #{ligne_tresorerie(entry)}"
            end
          end
        end

        def plan_retrait(arguments)
          entry = ligne_de_caisse!(arguments["ligne"])
          motif!({ "motif" => @motif })
          raise Error, "Cette ligne est déjà retirée." if entry.status == "excluded"
          raise Error, "#{nom_mois(entry.entry_date.beginning_of_month)} est arrêté : la feuille ne se modifie plus." if MonthClosing.closed?(entry.entry_date)

          Plan.new(resume: "RETIRER #{ligne_tresorerie(entry)}\nMotif : « #{@motif} ». Son écriture est contre-passée ; la ligne " \
                           "reste visible parmi les lignes retirées.",
                   empreinte: [etat_de(entry), signature(arguments)], donnees: { geste: "retirer", id: entry.id })
        end

        def ligne_de_caisse!(reference)
          entry = ligne!(reference)
          raise Error, "La ligne ##{entry.id} n'est pas une ligne de caisse (#{entry.cash_account.kind_label})." unless entry.cash_account.kind == "cash"

          entry
        end

        def motif_caisse!(reference)
          texte = reference.to_s.strip.delete_prefix("#")
          return CashMotif.actives.find_by(id: texte) || raise(Error, "Aucun motif de caisse ##{texte}.") if texte.match?(/\A\d+\z/)

          trouves = CashMotif.actives.where("label ILIKE ?", "%#{CashMotif.sanitize_sql_like(texte)}%").ordered.to_a
          exact = trouves.find { |m| m.label.casecmp?(texte) }
          return exact if exact
          return trouves.first if trouves.one?
          raise Error, "Aucun motif de caisse ne correspond à « #{texte} »." if trouves.empty?

          raise Error, "Plusieurs motifs correspondent à « #{texte} » : #{trouves.map(&:label).join(', ')}."
        end
      end
    end
  end
end
