module Portal
  # Une personne qui vend ou anime chez nous sans être salariée (Michael,
  # 2026-10-22) : l'espace artisan devient l'espace des partenaires.
  #
  # Ce n'est PAS un compte : c'est une adresse email, et les fiches qui la
  # portent. Aujourd'hui la fiche d'artisan du dépôt-vente (`Consignor`) ;
  # demain la fiche du porteur d'activité et celle du cuistot des événements.
  # Une même personne peut tenir plusieurs rôles — Eline dépose ses créations,
  # vend ses cookies aux événements et anime — et l'espace lui montre un
  # onglet par rôle qu'elle tient.
  #
  # Rien ne se mémorise ici : chaque requête relit les fiches. Un artisan dont
  # on ferme l'espace perd son onglet tout de suite, sans attendre que son
  # cookie expire.
  class Partner
    # Un onglet par rôle, dans cet ordre : son libellé et la page qui l'ouvre.
    ROLES = {
      consignment: { label: "Dépôt-vente", route: :portal_consignments_path }
    }.freeze

    attr_reader :email

    # Le partenaire de cette adresse, ou nil si elle n'ouvre aucun rôle.
    def self.for_email(email)
      partner = new(email)
      partner.roles.any? ? partner : nil
    end

    def initialize(email)
      @email = email.to_s.strip.downcase
    end

    # La fiche d'artisan dont l'espace est ouvert (`Consignor.for_portal_email`).
    def consignor
      return @consignor if defined?(@consignor)

      @consignor = Consignor.for_portal_email(email)
    end

    def roles
      ROLES.keys.select { |role| holds?(role) }
    end

    def role?(role) = roles.include?(role)

    def name = consignor&.name.presence || email

    private

    def holds?(role)
      case role
      when :consignment then consignor.present?
      end
    end
  end
end
