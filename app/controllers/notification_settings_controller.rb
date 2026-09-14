# Paramètres > Notifications (epic #242, phase 2, décision 3).
#
# Un seul réglage pour l'instant : qui est « la comptabilité ». C'est la liste
# d'adresses que la phase 3 utilisera comme destinataire des événements
# comptables (facture à valider, information demandée). La liste est stockée
# dans `Setting`, donc modifiable sans redéploiement.
class NotificationSettingsController < BaseController
  ACCOUNTING_EMAILS_KEY = "accounting_notification_emails".freeze

  breadcrumb "Notifications", :notification_settings_path, match: :exact

  def show
    @emails = self.class.accounting_emails.join(", ")
  end

  def update
    emails = parse_emails(params.dig(:notification_settings, :accounting_notification_emails))
    invalid = emails.reject { |email| email.match?(URI::MailTo::EMAIL_REGEXP) }

    if invalid.any?
      @emails = params.dig(:notification_settings, :accounting_notification_emails).to_s
      flash.now[:alert] = "Adresse invalide : #{invalid.to_sentence}."
      return render :show, status: :unprocessable_entity
    end

    Setting.set(ACCOUNTING_EMAILS_KEY, emails.join(","))
    redirect_to notification_settings_path, notice: "Les destinataires comptables ont été enregistrés."
  end

  # Les adresses déclarées, sans doublon ni vide. Point de lecture unique — la
  # phase 3 passe par ici, jamais par `Setting[...]` en direct.
  def self.accounting_emails
    Setting[ACCOUNTING_EMAILS_KEY].to_s.split(",").map { |email| email.strip.downcase }.reject(&:blank?).uniq
  end

  # Les `User` derrière ces adresses — ce sont eux qui reçoivent les
  # notifications comptables.
  def self.accounting_users
    return User.none if accounting_emails.empty?

    User.where("LOWER(email) IN (?)", accounting_emails)
  end

  private

  # Virgules, points-virgules ou retours à la ligne : on accepte les trois, la
  # saisie vient souvent d'un copier-coller.
  def parse_emails(raw)
    raw.to_s.split(/[,;\n]/).map { |email| email.strip.downcase }.reject(&:blank?).uniq
  end

  def set_presenters
    @menu_presenter = Components::MenuPresenter.new(
      active_primary: "settings",
      active_secondary: "notifications"
    )
    @settings_view = true
  end
end
