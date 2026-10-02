module OnCall
  # Qui décroche la ligne de garde à un instant donné.
  #
  # La garde est posée au jour (`HumanRole` rôle 1 « Veilleur·euse ») ; la garde
  # du jour J court de J à l'heure de bascule jusqu'à J+1 à la même heure. Le
  # calcul se fait en heure locale de Bruxelles : l'heure d'été ne décale rien.
  #
  # Plusieurs titulaires le même jour : un seul téléphone sonne, celui du
  # veilleur désigné (`phone_holder`), sinon le premier titulaire inscrit qui a
  # un numéro. Les suppléants (`backup`) servent de deuxième marche.
  class Resolver
    WATCHMAN_ROLE_ID = 1

    attr_reader :duty_date

    def initialize(at: Time.current, duty_date: nil, handover_hour: Config.handover_hour)
      @duty_date = duty_date || self.class.duty_date_for(at, handover_hour)
    end

    def self.duty_date_for(at, handover_hour)
      local = at.in_time_zone(Config::TIME_ZONE)
      local.hour < handover_hour ? local.to_date - 1 : local.to_date
    end

    # Le veilleur dont le téléphone sonne en premier, ou nil.
    def on_call
      titulars.find { |human_role| human_role.human.phone.present? }&.human
    end

    # Le suppléant appelé si le veilleur ne décroche pas, ou nil.
    def backup
      roles(:backup).find { |human_role| human_role.human.phone.present? }&.human
    end

    # Les titulaires du jour, le porteur du téléphone en tête.
    def titulars
      roles(:selected).sort_by { |human_role| [human_role.phone_holder? ? 0 : 1, human_role.id] }
    end

    private

    # Un membre désactivé sort du default_scope des Humans : `human` revient nil
    # et on l'écarte — on n'appelle pas quelqu'un qui a quitté le lieu.
    def roles(status)
      @roles ||= {}
      @roles[status] ||= HumanRole
        .where(role_id: WATCHMAN_ROLE_ID, date: duty_date, status: status)
        .includes(:human)
        .order(:id)
        .select { |human_role| human_role.human.present? }
    end
  end
end
