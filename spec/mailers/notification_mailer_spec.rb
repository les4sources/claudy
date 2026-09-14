require "rails_helper"

# Epic #242, phase 2 — la copie par email d'une notification. Un seul gabarit
# pour tous les `kind` : ajouter un type d'événement ne demande pas un mailer.
RSpec.describe NotificationMailer do
  let(:recipient) { User.create!(email: "sebastien-mail@les4sources.be", password: "password123") }

  let(:notification) do
    Notifications::Notify.new(recipient: recipient, kind: "comment",
                              title: "La comptabilité a commenté le séjour de Martin",
                              body: "Il manque le ticket du 12/08",
                              url: "/stays/42#comment-7")
                         .tap(&:run).notification
  end

  it "prend le titre de la notification comme objet" do
    mail = described_class.notify(notification)

    expect(mail.subject).to eq("La comptabilité a commenté le séjour de Martin")
    expect(mail.to).to eq([recipient.email])
  end

  # Le lien passe par `/notifications/:id`, pas par l'objet en direct : c'est ce
  # qui marque la notification lue au passage.
  it "mène au centre de notifications, qui redirige vers l'objet" do
    body = described_class.notify(notification).body.encoded

    expect(body).to include("/notifications/#{notification.id}")
    expect(body).to include("Il manque le ticket du 12/08")
  end
end
