module Mcp
  module Tools
    module Finances
      # Comptabilité > Stripe (StripeController#update_mode) : changer la façon
      # dont un compte Stripe entre en comptabilité. Même garde-fou que l'écran
      # (`Finance::StripeAccounts#change_mode!`).
      class ModeStripe < Ecriture
        include Commun

        MODES = { "par_versement" => "per_payout", "grand_livre" => "ledger" }.freeze

        tool "mode_stripe",
             title: "Changer le mode d'un compte Stripe",
             description: "Passe un compte Stripe en mode par_versement (chaque versement est ventilé quand il arrive " \
                          "en banque) ou grand_livre (chaque transaction entre au journal et s'affecte par catégorie, " \
                          "via correspondance_stripe). C'est une décision : elle change la façon dont TOUT le compte " \
                          "entre en comptabilité. Revenir au mode par versement est refusé dès qu'une transaction a été " \
                          "importée en grand livre. L'état des comptes : comptes_stripe.",
             schema: {
               properties: {
                 compte: { type: "string", description: "Le compte de trésorerie Stripe (nom, ex. « Stripe Claudy »)." },
                 mode: { type: "string", enum: MODES.keys }
               },
               required: %w[compte mode]
             }

        private

        def planifier(arguments)
          compte = par_nom!(CashAccount.stripe, arguments["compte"], "compte Stripe")
          mode = MODES[arguments["mode"].to_s] || raise(Error, "mode : #{MODES.keys.join(' ou ')}.")
          raise Error, "#{compte.name} est déjà en mode « #{compte.stripe_mode_label} »." if compte.stripe_mode == mode
          if mode == "per_payout" && ::Finance::StripeAccounts.new.ledger_transactions?(compte)
            raise Error, "Refusé : ce compte a déjà des transactions importées en mode grand livre, revenir au mode " \
                         "par versement laisserait ces lignes sans mode."
          end

          Plan.new(resume: "#{compte.name} : « #{compte.stripe_mode_label} » → « #{CashAccount::STRIPE_MODE_LABELS[mode]} ».\n" \
                           "Change la façon dont tout ce compte entre en comptabilité.",
                   empreinte: [etat_de(compte), mode], donnees: { id: compte.id, mode: mode })
        end

        def appliquer(plan)
          compte = CashAccount.find(plan.donnees[:id])
          metier! { ::Finance::StripeAccounts.new.change_mode!(compte, plan.donnees[:mode]) }
          "#{compte.name} : #{compte.stripe_mode_label}."
        end
      end
    end
  end
end
