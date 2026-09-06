module Kitchen
  # Le programme des deux semaines, envoyé le vendredi (epic #219, phase 7).
  # Stéphanie fait ses courses le dimanche : c'est le vendredi qu'elle a besoin
  # de savoir ce qui l'attend.
  #
  # Le garde-fou est la SEMAINE ISO, pas la date : un cron qui rejoue, ou une
  # relance à la main le samedi, ne doit pas renvoyer le même programme deux
  # fois. `FORCE=1` passe outre, pour les essais.
  class WeeklyDigest
    HORIZON_DAYS = 14
    LAST_SENT_KEY = "kitchen.digest_last_sent_on".freeze

    def initialize(force: false)
      @force = force
    end

    def run
      return "déjà envoyé cette semaine (#{Setting[LAST_SENT_KEY]}) — FORCE=1 pour forcer." unless sendable?

      orders = scope.to_a
      return "aucune prestation dans les #{HORIZON_DAYS} prochains jours." if orders.empty?

      sent = deliver_to_each(orders)
      Setting.set(LAST_SENT_KEY, Date.current.iso8601)
      "#{sent} email(s) envoyé(s) pour #{orders.size} prestation(s)."
    end

    private

    def sendable?
      return true if @force

      last = Setting[LAST_SENT_KEY].presence
      return true if last.blank?

      Date.parse(last).cweek != Date.current.cweek || Date.parse(last).cwyear != Date.current.cwyear
    rescue ArgumentError
      true
    end

    def scope
      MealOrder.where(status: %w[inquiry requested confirmed])
               .where.not(validation: "refused")
               .where(date: Date.current..(Date.current + HORIZON_DAYS))
               .includes(:responsible_human, stay: :customer)
               .chronological
    end

    # Une ligne sans responsable revient au responsable par défaut de sa
    # famille : sans ça, personne ne la verrait passer.
    def deliver_to_each(orders)
      orders.group_by { |order| order.responsible_human || Kitchen::Config.default_human(order.family) }
            .count do |human, group|
              next false if human.nil? || human.email.blank?

              KitchenMailer.weekly_digest(human, group).deliver_later
              true
            end
    end
  end
end
