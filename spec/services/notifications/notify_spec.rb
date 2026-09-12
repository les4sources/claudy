require "rails_helper"

# Epic #242, phase 2 — `Notifications::Notify` est le SEUL point de création
# d'une notification : la ligne, l'email et la trace de l'envoi partent
# ensemble ou pas du tout.
RSpec.describe Notifications::Notify do
  include ActiveJob::TestHelper

  let(:recipient) { User.create!(email: "sebastien@les4sources.be", password: "password123") }
  let(:actor)     { User.create!(email: "compta@les4sources.be", password: "password123") }

  def notify(**overrides)
    described_class.new(**{
      recipient: recipient, actor: actor, kind: "comment",
      title: "La comptabilité a commenté", url: "/stays/1"
    }.merge(overrides))
  end

  before { ActionMailer::Base.deliveries.clear }

  it "crée la notification et envoie l'email quand le destinataire le veut" do
    perform_enqueued_jobs { expect(notify.run).to be(true) }

    notification = Notification.last
    expect(notification.recipient).to eq(recipient)
    expect(notification.kind).to eq("comment")
    expect(notification.emailed_at).to be_present
    expect(ActionMailer::Base.deliveries.map(&:to).flatten).to include(recipient.email)
    expect(ActionMailer::Base.deliveries.last.subject).to eq("La comptabilité a commenté")
  end

  it "n'envoie pas d'email quand le destinataire l'a coupé, mais crée la notification" do
    recipient.update!(notify_by_email: false)

    perform_enqueued_jobs { expect(notify.run).to be(true) }

    expect(Notification.count).to eq(1)
    expect(Notification.last.emailed_at).to be_nil
    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "ne notifie jamais l'auteur de son propre geste" do
    expect(notify(recipient: actor).run).to be(false)
    expect(Notification.count).to be_zero
  end

  it "ignore un destinataire absent" do
    expect(notify(recipient: nil).run).to be(false)
    expect(Notification.count).to be_zero
  end

  describe ".broadcast" do
    it "dédoublonne les destinataires et rend les notifications créées" do
      autre = User.create!(email: "autre@les4sources.be", password: "password123")

      created = described_class.broadcast(
        recipients: [recipient, autre, recipient, nil, actor],
        actor: actor, kind: "comment", title: "Un commentaire", url: "/stays/1"
      )

      expect(created.size).to eq(2)
      expect(Notification.pluck(:recipient_id)).to match_array([recipient.id, autre.id])
    end
  end

  # Anti-critère de l'epic : rien d'autre dans `app/` ne fabrique une
  # notification. Le jour où quelqu'un écrit `Notification.create` dans un
  # contrôleur, l'email et la trace deviennent facultatifs — cette spec est là
  # pour que ça ne passe pas inaperçu.
  it "est le seul endroit de app/ qui instancie une Notification" do
    offenders = Dir.glob(Rails.root.join("app/**/*.rb")).reject do |path|
      path.include?("app/services/notifications/")
    end.select do |path|
      # Les COMMENTAIRES ont le droit de nommer `Notification.create` — c'est
      # même comme ça qu'on explique la règle. Seul le code compte.
      File.readlines(path).any? { |line| !line.strip.start_with?("#") && line.match?(/Notification\.(new|create)/) }
    end

    expect(offenders).to be_empty
  end
end
