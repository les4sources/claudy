require "rails_helper"

# Epic #242, phase 2 — la cloche, la page, la préférence, et l'atterrissage.
RSpec.describe "Notifications", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user)  { User.create!(email: "sebastien-notif@les4sources.be", password: "password123") }
  let(:autre) { User.create!(email: "quelquun-dautre@les4sources.be", password: "password123") }

  # Le seul point de création, y compris dans les specs : une notification
  # forgée à la main ici passerait à côté de ce que le service garantit.
  def notify(recipient: user, title: "Un titre", url: "/stays/42", **rest)
    Notifications::Notify.new(recipient: recipient, kind: "comment", title: title, url: url, **rest)
                         .tap(&:run).notification
  end

  before { sign_in user }

  describe "GET /notifications" do
    it "liste les notifications de l'utilisateur, et de lui seul" do
      notify(title: "Pour moi")
      notify(recipient: autre, title: "Pour quelqu'un d'autre")

      get notifications_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Pour moi")
      expect(response.body).not_to include("Pour quelqu&#39;un d&#39;autre")
    end

    it "annonce le nombre de non-lues" do
      notify(title: "Une")
      notify(title: "Deux")

      get notifications_path

      expect(response.body).to include("2 notifications non lues")
    end
  end

  # Les notifications ont quitté la cloche de la barre pour la colonne du tableau
  # de bord (Michael 2026-09-20). Ce qui compte ici, c'est qu'elles s'affichent
  # OUVERTES sur cette page — et qu'elles n'y dépendent pas du membre regardé :
  # le sélecteur peut pointer n'importe qui, les notifications restent celles du
  # compte connecté.
  describe "la colonne du tableau de bord" do
    it "montre les notifications du compte connecté" do
      notify(title: "Une notification")

      get dashboard_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Une notification")
      expect(response.body).to include("Notifications")
    end

    it "dit qu'il n'y a rien plutôt que de laisser un trou" do
      get dashboard_path

      expect(response.body).to include("Rien pour l'instant")
    end

    it "ne montre pas celles de quelqu'un d'autre" do
      notify(recipient: autre, title: "Pour quelqu'un d'autre")

      get dashboard_path

      expect(response.body).not_to include("Pour quelqu&#39;un d&#39;autre")
    end
  end

  # La cloche n'existe plus dans la barre : si elle y revient, c'est une
  # régression, pas un ajout.
  describe "la barre de navigation" do
    it "ne porte plus de cloche" do
      get notifications_path

      expect(response.body).not_to include(%(id="notifications-bell"))
    end
  end

  describe "GET /notifications/:id" do
    it "marque la notification lue et atterrit sur l'objet" do
      notification = notify(url: "/stays/42#comment-7")

      get notification_path(notification)

      expect(response).to redirect_to("/stays/42#comment-7")
      expect(notification.reload.read_at).to be_present
    end

    it "ne laisse pas ouvrir la notification d'un autre" do
      notification = notify(recipient: autre)

      expect { get notification_path(notification) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    # L'`url` est posée par l'application, mais elle est STOCKÉE : une valeur
    # abîmée ne doit pas devenir une redirection ouverte.
    it "refuse de renvoyer vers l'extérieur" do
      notification = notify(url: "/ok")
      notification.update_column(:url, "https://exemple.test/phishing")

      get notification_path(notification)

      expect(response).to redirect_to(root_path)
    end
  end

  describe "POST /notifications/read_all" do
    it "marque tout lu, pour lui seul" do
      notify(title: "Une")
      notify(title: "Deux")
      sienne = notify(recipient: autre, title: "Pas touche")

      post read_all_notifications_path

      expect(user.notifications.unread.count).to be_zero
      expect(sienne.reload.read_at).to be_nil
    end
  end

  describe "PATCH /notifications/preferences" do
    it "coupe et rétablit l'envoi par email" do
      patch preferences_notifications_path, params: { user: { notify_by_email: "0" } }
      expect(user.reload.notify_by_email).to be(false)

      patch preferences_notifications_path, params: { user: { notify_by_email: "1" } }
      expect(user.reload.notify_by_email).to be(true)
    end
  end
end
