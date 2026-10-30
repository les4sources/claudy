module PurchaseInvoices
  # Le récapitulatif du lundi : les factures d'achat qui attendent l'aval d'un
  # pôle (Michael, 2026-10-30). Il remplace l'email qui partait à chaque envoi
  # en validation : une facture par email, c'était trop d'emails.
  #
  # Un email par membre, avec TOUTES les factures de ses pôles. Rien ne part
  # quand rien n'attend : un récapitulatif vide n'apprend rien à personne.
  #
  # Le garde-fou est la SEMAINE ISO, comme le programme de la cuisine : un cron
  # qui rejoue, ou une relance à la main le mardi, ne renvoie pas la même liste.
  # `FORCE=1` passe outre, pour les essais.
  class ValidationDigest
    LAST_SENT_KEY = "purchase_invoices.validation_digest_last_sent_on".freeze

    def initialize(force: false)
      @force = force
    end

    def run
      return "déjà envoyé cette semaine (#{Setting[LAST_SENT_KEY]}) — FORCE=1 pour forcer." unless sendable?

      invoices = scope.to_a
      return "aucune facture à valider." if invoices.empty?

      # Posé AVANT les envois, pour la même raison que la cuisine : un échec en
      # cours de route ne doit pas faire renvoyer la liste à ceux qui l'ont eue.
      Setting.set(LAST_SENT_KEY, Date.current.iso8601)
      by_recipient = group_by_recipient(invoices)
      by_recipient.each do |human, theirs|
        PurchaseInvoiceMailer.validation_digest(human, theirs).deliver_later
      end
      "#{by_recipient.size} email(s) envoyé(s) pour #{invoices.size} facture(s) à valider."
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
      PurchaseInvoice.with_status("to_validate")
                     .where.not(validation_team_id: nil)
                     .includes(:third_party, :legal_entity, :validation_team)
                     .by_due_date
    end

    # Les mêmes destinataires que l'ancien email : les membres du pôle qui ont
    # une adresse (`validation_recipients`). Un membre de deux pôles reçoit un
    # seul email, avec les factures des deux.
    def group_by_recipient(invoices)
      invoices.each_with_object(Hash.new { |h, k| h[k] = [] }) do |invoice, acc|
        invoice.validation_recipients.each { |human| acc[human] << invoice }
      end
    end
  end
end
