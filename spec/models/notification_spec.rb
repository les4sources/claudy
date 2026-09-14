require "rails_helper"

# Epic #242, phase 2 — le modèle `Notification`.
RSpec.describe Notification do
  let(:recipient) { User.create!(email: "destinataire@les4sources.be", password: "password123") }

  def build_notification(**overrides)
    described_class.new({
      recipient: recipient, kind: "comment", title: "Un titre", url: "/stays/1"
    }.merge(overrides))
  end

  it "refuse une notification sans destination" do
    notification = build_notification(url: nil)

    expect(notification).not_to be_valid
    expect(notification.errors[:url]).to be_present
  end

  it "refuse une notification sans titre ni type" do
    expect(build_notification(title: nil)).not_to be_valid
    expect(build_notification(kind: nil)).not_to be_valid
  end

  it "accepte un objet notifiable absent — la notification survit à son objet" do
    notification = build_notification(notifiable: nil)

    expect(notification).to be_valid
  end

  describe "#mark_read!" do
    it "date la lecture une seule fois" do
      notification = build_notification.tap(&:save!)

      notification.mark_read!
      first_read = notification.reload.read_at
      expect(first_read).to be_present

      # Pas de voyage dans le temps : `mark_read!` doit sortir tout de suite
      # quand la notification est déjà lue, sans écrire une seconde fois.
      expect { notification.mark_read! }.not_to(change { notification.reload.read_at })
    end
  end

  it "compte les non-lues d'un utilisateur" do
    build_notification.save!
    build_notification(title: "Deux").save!
    build_notification(title: "Trois").tap(&:save!).mark_read!

    expect(recipient.unread_notifications_count).to eq(2)
  end
end
