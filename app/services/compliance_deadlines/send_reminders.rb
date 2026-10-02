module ComplianceDeadlines
  # Les rappels de l'échéancier comptable — ce que Notion n'a jamais fait.
  #
  # Trois paliers : à J-14 (le temps de réunir les pièces), à J-3 (le temps de
  # le faire), puis en retard — et tant que c'est en retard, une fois par
  # semaine. Chaque palier ne part qu'UNE fois : l'échéance retient le dernier
  # palier envoyé et sa date, si bien que la tâche quotidienne peut tourner deux
  # fois le même jour sans doubler un email.
  #
  # Une échéance soldée par sa facture n'est plus ouverte (`outstanding`) : elle
  # ne relance donc plus personne, sans qu'on ait eu à la cocher.
  class SendReminders < ServiceBase
    include Routing

    EARLY_DAYS = 14
    LATE_DAYS = 3
    OVERDUE_EVERY_DAYS = 7

    def initialize(on: Date.current)
      @on = on
    end

    def run = catch_error(context: { on: @on }) { run! }

    # Rend le nombre d'échéances rappelées.
    def run!
      due = ComplianceDeadline.outstanding
                              .where(due_on: ..(@on + EARLY_DAYS))
                              .includes(compliance_obligation: %i[legal_entity responsible_user])
                              .ordered

      due.count { |deadline| remind(deadline) }
    end

    private

    def remind(deadline)
      stage = stage_for(deadline)
      return false unless send?(deadline, stage)

      recipients = deadline.compliance_obligation.reminder_recipients
      Notifications::Notify.broadcast(
        recipients: recipients,
        kind: "compliance_deadline",
        title: title_for(deadline, stage),
        body: body_for(deadline),
        url: finance_compliance_deadline_url(deadline),
        notifiable: deadline
      )
      deadline.update_columns(last_reminder_stage: stage, last_reminded_on: @on)
      true
    end

    def stage_for(deadline)
      days = deadline.days_left(@on)
      return "overdue" if days.negative?
      return "soon" if days <= LATE_DAYS

      "early"
    end

    # Un palier déjà envoyé ne repart pas — sauf le retard, qui revient chaque
    # semaine : une échéance dépassée qu'on ne rappelle plus est une échéance
    # qu'on oublie.
    def send?(deadline, stage)
      return true if deadline.last_reminder_stage != stage
      return false unless stage == "overdue"

      deadline.last_reminded_on.nil? || deadline.last_reminded_on <= @on - OVERDUE_EVERY_DAYS
    end

    def title_for(deadline, stage)
      days = deadline.days_left(@on)
      prefix = case stage
               when "overdue" then "En retard de #{-days} j"
               when "soon" then days.zero? ? "Aujourd'hui" : "Dans #{days} j"
               else "Dans #{days} j"
               end
      "#{prefix} : #{deadline.display_title} (#{deadline.legal_entity.name})"
    end

    def body_for(deadline)
      parts = ["Échéance le #{I18n.l(deadline.due_on, format: :long)}."]
      parts << "Paiement : la facture n'est pas encore encodée." if deadline.payment? && deadline.purchase_invoice.nil?
      parts << deadline.compliance_obligation.instructions if deadline.compliance_obligation.instructions.present?
      parts.join("\n\n")
    end
  end
end
