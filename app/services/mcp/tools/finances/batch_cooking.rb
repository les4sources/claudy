module Mcp
  module Tools
    module Finances
      # Finances > Batch cooking (BatchCookingSessionsController#index) : les
      # sessions récentes, qui a été servi, qui a cuisiné, et ce que ça a posé
      # sur les comptes.
      class BatchCooking < Base
        include Commun

        tool "batch_cooking",
             title: "Sessions de batch cooking",
             description: "Les sessions de batch cooking (#id, date, repas, personnes servies par compte, cuisiniers et " \
                          "portions, écritures posées), les plus récentes d'abord, et les tarifs du jour. Pour saisir " \
                          "ou corriger une session : enregistrer_batch_cooking.",
             schema: { properties: { session: { type: %w[integer string], description: "Une session (#id) en détail." } } }

        def call(arguments)
          sessions = if arguments["session"].present?
                       [BatchCookingSession.find_by(id: id!(arguments["session"], "session")) || raise(Error, "Aucune session ##{arguments['session']}.")]
                     else
                       BatchCookingSession.recent_first.limit(15).to_a
                     end
          tarifs = "Tarifs du jour : #{euros(Pricing::Rates.cents(::Finance::RecordBatchCooking::SERVING_RATE_KEY, on: Date.current))} " \
                   "par personne et par repas, #{euros(Pricing::Rates.cents(::Finance::RecordBatchCooking::COOK_RATE_KEY, on: Date.current))} " \
                   "par portion cuisinée."
          return "#{tarifs}\nAucune session." if sessions.empty?

          corps = sessions.map do |s|
            servis = s.servings.includes(:member_account).map { |sv| "#{sv.member_account&.code} #{sv.member_account&.name} × #{sv.people}" }
            cuistots = s.cooks.includes(:human).map { |c| "#{c.human&.name} #{format('%g', c.portions)}" }
            ecritures = AccountEntry.unscoped.where("idempotency_key LIKE ?", "#{::Finance::RecordBatchCooking::KEY_PREFIX}:#{s.id}:%")
            "Session ##{s.id} du #{s.cooked_on} · #{s.meals_count} repas · #{s.people_served} personne(s)" \
              "#{" · #{s.notes.squish.truncate(80)}" if s.notes.present?}\n" \
              "  Servis : #{servis.join(', ').presence || 'personne'}\n  Cuisiniers (portions) : #{cuistots.join(', ').presence || 'personne'}\n" \
              "  Écritures : #{ecritures.count} pour #{euros(ecritures.where('amount_cents > 0').sum(:amount_cents))} facturés"
          end
          "#{tarifs}\n\n#{corps.join("\n")}"
        end
      end
    end
  end
end
