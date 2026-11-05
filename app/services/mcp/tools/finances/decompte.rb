module Mcp
  module Tools
    module Finances
      # Finances > Décomptes (StatementsController) : émettre les décomptes
      # d'un mois, les envoyer par email, relancer, marquer réglé, et régénérer
      # ou annuler un décompte émis trop tôt, tant qu'il n'est pas parti.
      #
      # Rien ne part tout seul, comme à l'écran : chaque émission, envoi ou
      # relance est un geste explicite.
      class Decompte < Ecriture
        include Commun

        GESTES = {
          "emettre" => "émettre le décompte du mois (une fois le mois terminé) : il FIGE le solde et VERROUILLE les lignes du mois",
          "regenerer" => "remplacer un décompte émis mais jamais envoyé par un décompte qui reprend tout ce que le grand livre " \
                         "porte aujourd'hui sur le mois",
          "annuler" => "supprimer un décompte émis mais jamais envoyé et déverrouiller ses lignes (le compte revient « à émettre »)",
          "envoyer" => "envoyer le décompte par email au compte",
          "relancer" => "envoyer un email de relance",
          "marquer_regle" => "encaisser ce qui reste dû (règlement « moyen non précisé ») et marquer réglé"
        }.freeze

        tool "decompte",
             title: "Émettre, envoyer ou relancer un décompte",
             description: "#{GESTES.map { |cle, sens| "#{cle} : #{sens}" }.join(' ; ')}. Pour emettre : `mois` et `comptes` " \
                          "(ou `tous` : chaque compte actif au solde non nul sans décompte). Pour les autres : `decomptes` " \
                          "(identifiants rendus par decomptes). Envoyer et relancer ÉCRIVENT AUX FAMILLES.",
             schema: {
               properties: {
                 geste: { type: "string", enum: GESTES.keys },
                 mois: MOIS,
                 comptes: { type: "array", items: { type: "string" }, description: "Comptes (code SRC-… ou nom)." },
                 tous: { type: "boolean" },
                 decomptes: { type: "array", items: { type: %w[integer string] }, description: "Décomptes (#id)." }
               },
               required: %w[geste]
             }

        # L'email part pendant le geste (deliver_now) : le décompte ne passe
        # « envoyé » qu'une fois l'email parti, comme à l'écran.
        def self.transactionnel? = false

        private

        def planifier(arguments)
          geste = arguments["geste"].to_s
          raise Error, "geste : #{GESTES.keys.join(', ')}." unless GESTES.key?(geste)
          return plan_emission(arguments) if geste == "emettre"

          decomptes = Array(arguments["decomptes"]).map { |ref| decompte!(ref) }
          raise Error, "Donne les décomptes (identifiants rendus par decomptes)." if decomptes.empty?

          return plan_regeneration(geste, decomptes, arguments) if %w[regenerer annuler].include?(geste)

          lignes = decomptes.map { |s| send("ligne_#{geste}", s) }
          Plan.new(resume: lignes.join("\n"), empreinte: [decomptes.map { |s| etat_de(s) }, signature(arguments)],
                   donnees: { geste: geste, ids: decomptes.map(&:id) })
        end

        def appliquer(plan)
          d = plan.donnees
          return emettre(d) if d[:geste] == "emettre"
          return regenerer(d) if %w[regenerer annuler].include?(d[:geste])

          AccountStatement.where(id: d[:ids]).includes(member_account: :human).map do |statement|
            send(d[:geste], statement)
          end.join("\n")
        end

        def decompte!(reference)
          AccountStatement.includes(member_account: :human).find_by(id: id!(reference, "décompte")) ||
            raise(Error, "Aucun décompte ##{reference.to_s.delete('#')}.")
        end

        def destinataire(statement)
          compte = statement.member_account
          compte.contact_email.presence || compte.human&.email.presence
        end

        def entete(statement)
          "Décompte ##{statement.id} #{statement.member_account.code} #{statement.member_account.name} " \
            "(#{nom_mois(statement.period_month)}, #{statement.status_label.downcase}, solde #{euros(statement.closing_balance_cents)})"
        end

        def ligne_envoyer(statement)
          raise Error, "#{entete(statement)} : pas d'email de contact, ajoute-le sur la fiche du compte." if destinataire(statement).nil?

          "#{entete(statement)} → email à #{destinataire(statement)}#{' (déjà envoyé une fois)' if statement.sent_at}"
        end

        def ligne_relancer(statement)
          raise Error, "#{entete(statement)} : pas d'email de contact." if destinataire(statement).nil?

          "#{entete(statement)} → relance n° #{statement.reminders_count.to_i + 1} à #{destinataire(statement)}"
        end

        def ligne_marquer_regle(statement)
          raise Error, "#{entete(statement)} : déjà réglé." if statement.settled?

          montant = [[statement.closing_balance_cents, statement.member_account.balance_cents].min, 0].max
          "#{entete(statement)} → #{montant.positive? ? "règlement de #{euros(montant)} encaissé aujourd'hui (moyen non précisé)" : 'rien à encaisser'}, puis réglé"
        end

        def envoyer(statement)
          FinanceStatementMailer.statement(statement).deliver_now
          statement.update!(status: "sent", sent_at: Time.current)
          "Envoyé à #{destinataire(statement)} : #{entete(statement)}"
        end

        def relancer(statement)
          FinanceStatementMailer.reminder(statement).deliver_now
          statement.update!(reminders_count: statement.reminders_count.to_i + 1, last_reminder_at: Time.current)
          "Relance envoyée à #{destinataire(statement)} : #{entete(statement)}"
        end

        # Le bouton « Marquer réglé » : il ENCAISSE, plafonné par le solde réel,
        # sinon l'écran dirait « réglé » pendant que le grand livre réclame.
        def marquer_regle(statement)
          AccountStatement.transaction do
            statement.lock!
            next "#{entete(statement)} : déjà réglé." if statement.settled?

            montant = [[statement.closing_balance_cents, statement.member_account.balance_cents].min, 0].max
            if montant.positive?
              ::Finance::RecordSettlement.new(
                member_account: statement.member_account, amount_cents: montant, received_on: Date.current,
                reference: "Décompte #{statement.period_month.strftime('%m/%Y')}",
                notes: "Encaissement déclaré depuis Claude (écran des décomptes) — moyen et date non précisés.",
                whodunnit: whodunnit
              ).run!
            end
            statement.update!(status: "settled")
            "Réglé : #{entete(statement)}"
          end
        end

        # Régénérer, c'est annuler puis réémettre, tout ou rien : l'aperçu le
        # joue à blanc pour montrer le nouveau solde à côté de l'ancien.
        def plan_regeneration(geste, decomptes, arguments)
          reemettre = geste == "regenerer"
          lignes = simuler do
            decomptes.map do |statement|
              couvertes = statement.account_entries.count
              resultat = ::Finance::RegenerateStatement.new(statement: AccountStatement.find(statement.id),
                                                            whodunnit: whodunnit, reissue: reemettre).run!
              if reemettre
                "#{entete(statement)} → nouveau solde #{euros(resultat.statement.closing_balance_cents)} " \
                  "(ouverture #{euros(resultat.statement.opening_balance_cents)}, + #{euros(resultat.statement.debits_cents)}, " \
                  "#{euros(resultat.statement.credits_cents)})"
              else
                "#{entete(statement)} → annulé, #{couvertes} ligne(s) déverrouillée(s)"
              end
            rescue ::Finance::IssueStatement::Refused => e
              "#{entete(statement)} : REFUSÉ — #{e.message}"
            end
          end
          titre = reemettre ? "Régénérer" : "Annuler"
          Plan.new(resume: "#{titre} #{decomptes.size} décompte(s) (rien n'est envoyé) :\n#{lignes.join("\n")}",
                   empreinte: [decomptes.map { |s| etat_de(s) }, lignes, signature(arguments)],
                   donnees: { geste: geste, ids: decomptes.map(&:id) })
        end

        def regenerer(d)
          reemettre = d[:geste] == "regenerer"
          AccountStatement.where(id: d[:ids]).includes(member_account: :human).map do |statement|
            metier! do
              resultat = ::Finance::RegenerateStatement.new(statement: statement, whodunnit: whodunnit, reissue: reemettre).run!
              if reemettre
                "Décompte ##{resultat.statement.id} émis à la place du ##{statement.id} : #{statement.member_account.code} " \
                  "#{statement.member_account.name}, #{euros(resultat.previous[:closing_balance_cents])} → " \
                  "#{euros(resultat.statement.closing_balance_cents)}"
              else
                "Décompte ##{statement.id} annulé : #{statement.member_account.code} #{statement.member_account.name}"
              end
            end
          rescue Error => e
            "#{statement.member_account.code} #{statement.member_account.name} : refusé — #{e.message}"
          end.join("\n")
        end

        def plan_emission(arguments)
          mois = mois!(arguments["mois"], defaut: Date.current.beginning_of_month)
          comptes = if arguments["tous"]
                      deja = AccountStatement.for_month(mois).select(:member_account_id)
                      MemberAccount.ordered.where(active: true).where.not(id: deja).reject { |c| c.balance_cents.zero? }
                    else
                      Array(arguments["comptes"]).map { |ref| compte!(ref) }.uniq
                    end
          raise Error, "Donne les comptes, ou tous: true." if comptes.empty?

          lignes = simuler do
            comptes.map do |compte|
              s = ::Finance::IssueStatement.new(member_account: MemberAccount.find(compte.id), month: mois, whodunnit: whodunnit).run!
              "#{compte.code} #{compte.name} : ouverture #{euros(s.opening_balance_cents)}, + #{euros(s.debits_cents)}, " \
                "#{euros(s.credits_cents)} → solde #{euros(s.closing_balance_cents)}" \
                "#{' ⚠ aucune ligne de bar ce mois-ci : la feuille de bar est-elle saisie ?' if ::Finance::IssueStatement.bar_missing?(compte, mois)}"
            rescue ::Finance::IssueStatement::Refused => e
              "#{compte.code} #{compte.name} : REFUSÉ — #{e.message}"
            end
          end
          Plan.new(resume: "Émettre les décomptes de #{nom_mois(mois)} (les lignes du mois seront verrouillées) :\n#{lignes.join("\n")}",
                   empreinte: [comptes.map(&:id), lignes, signature(arguments)],
                   donnees: { geste: "emettre", mois: mois.iso8601, comptes: comptes.map(&:id) })
        end

        def emettre(d)
          mois = Date.iso8601(d[:mois])
          resultats = MemberAccount.where(id: d[:comptes]).order(:name).map do |compte|
            metier! do
              s = ::Finance::IssueStatement.new(member_account: compte, month: mois, whodunnit: whodunnit).run!
              "Décompte ##{s.id} émis : #{compte.code} #{compte.name}, solde #{euros(s.closing_balance_cents)}"
            end
          rescue Error => e
            "#{compte.code} #{compte.name} : refusé — #{e.message}"
          end
          resultats.join("\n")
        end
      end
    end
  end
end
