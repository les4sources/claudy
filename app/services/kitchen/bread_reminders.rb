module Kitchen
  # Rappel « commande le pain » cinq jours avant (epic #219, phase 7). Michael
  # l'a demandé pour toutes les familles, pas seulement les buffets.
  #
  # L'idempotence tient à `bread_reminder_sent_at` : un cron qui rejoue le même
  # jour, ou deux fois dans la journée, n'envoie rien de plus.
  class BreadReminders
    LEAD_DAYS = 5

    def run
      orders = scope.to_a
      return "aucune prestation à J-#{LEAD_DAYS}." if orders.empty?

      sent = orders.count { |order| remind(order) }
      "#{sent} rappel(s) envoyé(s) sur #{orders.size} prestation(s) à J-#{LEAD_DAYS}."
    end

    private

    def scope
      # Fenêtre OUVERTE jusqu'à J-5, pas la date exacte : un jour de cron manqué
      # (déploiement, redémarrage) faisait perdre le rappel pour toujours.
      # `bread_reminder_sent_at` porte seul l'anti-doublon, la fenêtre large est
      # donc sans risque.
      MealOrder.billable
               .where(validation: "accepted", bread_reminder_sent_at: nil)
               .where(date: Date.current..(Date.current + LEAD_DAYS))
               .includes(:responsible_human, stay: :customer)
    end

    # Sans email, pas d'horodatage : la ligne reste éligible au prochain passage,
    # au cas où l'adresse serait renseignée entre-temps.
    def remind(order)
      # Même repli que le notifier et le digest : une ligne sans responsable
      # joignable revient au responsable par défaut de sa famille.
      email = (order.responsible_human || Kitchen::Config.default_human(order.family))&.email
      return false if email.blank?

      KitchenMailer.bread_reminder(order, email).deliver_later
      order.update_column(:bread_reminder_sent_at, Time.current)
      true
    end
  end
end
