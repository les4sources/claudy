module Mcp
  module Tools
    module Finances
      # Comptabilité > Caisse > Comptages (CashCountsController#create et
      # #update) : compter la caisse billet par billet. Même service que l'écran
      # (`Finance::RecordCashCount`) : un écart se cherche (brouillon, rien
      # d'écrit) ou s'assume (validé, ligne d'ajustement sur « Écarts de caisse »).
      class CompterCaisse < Ecriture
        include Commun

        ISSUES = { "retrouver" => "investigate", "assumer" => "unexplained" }.freeze

        tool "compter_caisse",
             title: "Compter la caisse",
             description: "Enregistre un comptage de caisse : la grille des billets et pièces comptés, comparée à ce " \
                          "que la comptabilité attend à cette date. Juste : comptage validé. Un écart demande un " \
                          "commentaire et une issue : retrouver (le comptage reste en brouillon, rien n'est écrit, on " \
                          "va saisir la ligne manquante avec ligne_caisse puis reprendre ce brouillon) ou assumer " \
                          "(comptage validé, l'écart est écrit en ligne de caisse « Écart de caisse » et comptabilisé). " \
                          "Un comptage validé ne se modifie plus. Les comptages passés : comptages_caisse.",
             schema: {
               properties: {
                 grille: {
                   type: "object",
                   description: "Quantité par billet ou pièce, la clé en euros : {\"50\": 2, \"20\": 5, \"2\": 7, \"0.5\": 4}. " \
                                "Billets 500 à 5, pièces 2 à 0.01.",
                   additionalProperties: { type: %w[integer string] }
                 },
                 date: DATE.merge(description: "Date du comptage. Défaut : aujourd'hui."),
                 commentaire: { type: "string", description: "Obligatoire s'il y a un écart." },
                 issue: { type: "string", enum: ISSUES.keys, description: "S'il y a un écart : retrouver ou assumer." },
                 comptage: { type: %w[integer string], description: "Pour reprendre un comptage en brouillon (#id, rendu par comptages_caisse)." },
                 caisse: { type: "string", description: "La caisse, s'il y en a plusieurs." }
               },
               required: %w[grille]
             }

        private

        def planifier(arguments)
          brouillon = brouillon!(arguments["comptage"])
          caisse = brouillon&.cash_account || caisse!(arguments["caisse"])
          grille = grille!(arguments["grille"])
          date = arguments["date"].present? ? date!(arguments["date"], "date") : (brouillon&.counted_on || Date.current)
          issue = if arguments["issue"].present?
                    ISSUES[arguments["issue"]] || raise(Error, "issue : #{ISSUES.keys.join(' ou ')}.")
                  end
          donnees = { caisse: caisse.id, comptage: brouillon&.id, grille: grille, date: date.iso8601,
                      commentaire: arguments["commentaire"].to_s.strip.presence, issue: issue }

          apres = simuler { enregistrer(donnees, "claude:#{user.email}") }
          Plan.new(resume: "#{caisse.name}, comptage du #{date}#{" (reprise du brouillon ##{brouillon.id})" if brouillon}\n" \
                           "#{detail_grille(grille)}\n#{consequence(apres)}",
                   empreinte: [donnees, brouillon && etat_de(brouillon),
                               ::Finance::CashSheet.accounting_balance(cash_account: caisse, up_to: date)],
                   donnees: donnees)
        end

        def appliquer(plan)
          comptage = enregistrer(plan.donnees, whodunnit)
          "Comptage ##{comptage.id} : #{consequence(comptage)}"
        end

        def enregistrer(donnees, auteur)
          metier! do
            ::Finance::RecordCashCount.new(
              cash_account: CashAccount.find(donnees[:caisse]), counted_on: Date.iso8601(donnees[:date]),
              denominations: donnees[:grille], comment: donnees[:commentaire], resolution: donnees[:issue],
              counted_by: user, count: donnees[:comptage] && CashCount.find(donnees[:comptage]), whodunnit: auteur
            ).run!
          end
        end

        def consequence(comptage)
          ecart = comptage.difference_cents.to_i
          base = "Compté #{euros(comptage.counted_cents)}, attendu #{euros(comptage.expected_cents)}"
          return "#{base} : caisse juste au centime, comptage validé." if ecart.zero?

          signe = "#{'+' if ecart.positive?}#{euros(ecart)}"
          if comptage.draft?
            "#{base} : écart de #{signe} gardé en BROUILLON, rien n'est écrit. Saisis la ligne manquante " \
              "(ligne_caisse), puis reprends ce comptage."
          else
            "#{base} : écart de #{signe} assumé, comptage validé et ligne « Écart de caisse » de #{signe} " \
              "écrite et comptabilisée sur la caisse."
          end
        end

        def detail_grille(grille)
          lignes = grille.sort_by { |unite, _| -unite.to_f }.map { |unite, nombre| "#{nombre} × #{euros((unite.to_f * 100).round)}" }
          "Grille : #{lignes.join(' · ')}"
        end

        # La grille telle que la saisit l'écran : clé en euros, quantité. Une
        # coupure qui n'existe pas est refusée plutôt qu'ignorée — le service,
        # lui, l'écarterait en silence et le total serait faux.
        def grille!(valeur)
          raise Error, "Donne la grille : {\"50\": 2, \"0.5\": 4}." unless valeur.is_a?(Hash) && valeur.any?

          valeur.each_with_object({}) do |(unite, nombre), grille|
            cents = (BigDecimal(unite.to_s.tr(',', '.').delete(' €')) * 100).to_i
            raise Error, "Coupure inconnue : « #{unite} »." unless CashCount::DENOMINATIONS.include?(cents)

            quantite = Integer(nombre.to_s, exception: false)
            raise Error, "Quantité illisible pour #{unite} : « #{nombre} »." if quantite.nil? || quantite.negative?
            next if quantite.zero?

            grille[CashCount.denomination_key(cents)] = quantite
          rescue ArgumentError
            raise Error, "Coupure illisible : « #{unite} »."
          end
        end

        def brouillon!(reference)
          return nil if reference.blank?

          comptage = CashCount.find_by(id: id!(reference, "comptage")) || raise(Error, "Aucun comptage ##{reference.to_s.delete('#')}.")
          raise Error, "Le comptage ##{comptage.id} est validé : il ne se modifie plus, refais-en un." if comptage.validated?

          comptage
        end
      end
    end
  end
end
