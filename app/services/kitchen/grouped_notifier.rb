module Kitchen
  # Un email par destinataire et par SAISIE, au lieu d'un par ligne (issue #266).
  #
  # `MealOrder` prévient la cuisine en `after_commit`, ligne par ligne : cocher
  # les cinq midis d'une semaine envoyait donc cinq « Nouvelle demande » à la
  # seconde près, pour ce qui est UNE demande dans la tête de tout le monde. La
  # saisie (`Kitchen::GridSubmission`) fait taire ces callbacks et passe ici une
  # fois sa transaction commitée.
  #
  # Trois règles tiennent le reste.
  #
  # PREMIÈRE : on groupe par DESTINATAIRE, pas globalement. Les repas partent
  # chez Stéphanie, les buffets chez la personne qui s'en charge — chacun ne
  # reçoit que ce qui le concerne.
  #
  # DEUXIÈME : les liens de réponse restent PAR LIGNE. C'est la ligne qui
  # s'accepte ou se refuse, et « je prends la semaine, sauf le mercredi midi »
  # doit rester possible.
  #
  # TROISIÈME : une seule ligne pour un destinataire = l'email `new_request`
  # habituel, inchangé. On ne groupe que ce qui a besoin de l'être.
  class GroupedNotifier
    MOMENT_ORDER = %w[midi gouter soir].freeze

    def initialize(orders:)
      @orders = Array(orders).compact
    end

    def call
      by_recipient.each { |recipient, lines| deliver(recipient, lines) }
    end

    private

    attr_reader :orders

    def by_recipient
      orders.group_by { |order| Kitchen::Notifier.responsible_email_for(order) }
    end

    def deliver(recipient, lines)
      if recipient.blank?
        Rails.logger.info(
          "[Kitchen::GroupedNotifier] #{lines.size} ligne(s) sans destinataire " \
          "(MealOrder #{lines.map(&:id).join(', ')})"
        )
        return
      end

      lines = chronological(refreshed(lines))
      mail = if lines.one?
               KitchenMailer.new_request(lines.first, recipient)
             else
               KitchenMailer.grouped_request(lines, recipient)
             end
      mail.deliver_later
    end

    # La remise de formule réécrit `price_cents` en `update_columns` pendant le
    # commit : les objets que la saisie tient en mémoire sont déjà périmés quand
    # on arrive ici, et l'email annoncerait le tarif plein.
    def refreshed(lines) = lines.map(&:reload)

    # L'email se lit dans l'ordre du séjour, pas dans celui des blocs du
    # formulaire : le mercredi midi vient après le mardi soir.
    def chronological(lines)
      lines.sort_by do |line|
        [line.date || Date.new(9999, 12, 31), MOMENT_ORDER.index(line.moment.to_s) || 9, line.id]
      end
    end
  end
end
