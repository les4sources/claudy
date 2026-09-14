require "rails_helper"

# Epic #242, phase 2, décision 4 — qui est prévenu quand on commente.
RSpec.describe Notifications::CommentPosted do
  let(:michael)   { User.create!(email: "michael@les4sources.be", password: "password123") }
  let(:sebastien) { User.create!(email: "sebastien@les4sources.be", password: "password123") }
  let(:compta)    { User.create!(email: "compta@les4sources.be", password: "password123") }

  let!(:category) { GatheringCategory.create!(name: "Collectif", color: "#0B3D3A") }
  let(:gathering) do
    Gathering.create!(gathering_category: category,
                      starts_at: Time.zone.parse("2026-03-03 18:00"),
                      ends_at: Time.zone.parse("2026-03-03 20:00"))
  end

  def comment_by(user, body: "Un mot")
    gathering.comments.create!(author: user, body: body)
  end

  before { ActionMailer::Base.deliveries.clear }

  it "prévient les auteurs des commentaires précédents, jamais soi-même" do
    comment_by(michael)
    comment_by(sebastien)

    described_class.call(comment_by(compta, body: "Il manque le ticket du 12/08"))

    expect(Notification.pluck(:recipient_id)).to match_array([michael.id, sebastien.id])
    expect(Notification.pluck(:kind).uniq).to eq(["comment"])
  end

  it "ne prévient personne sur le premier commentaire d'un objet sans destinataire déclaré" do
    described_class.call(comment_by(michael))

    expect(Notification.count).to be_zero
  end

  it "ajoute les destinataires déclarés par le modèle, sans doublon" do
    allow_any_instance_of(Gathering).to receive(:comment_recipients).and_return([sebastien, michael])
    comment_by(sebastien)

    described_class.call(comment_by(compta))

    expect(Notification.pluck(:recipient_id)).to match_array([sebastien.id, michael.id])
  end

  it "pointe sur la page de l'objet, ancrée sur le commentaire" do
    comment_by(michael)
    comment = comment_by(compta)

    described_class.call(comment)

    expect(Notification.last.url).to eq("/gatherings/#{gathering.id}#comment-#{comment.id}")
    expect(Notification.last.notifiable).to eq(gathering)
  end

  it "titre la notification avec l'auteur et l'objet, et résume le corps" do
    comment_by(michael)

    described_class.call(comment_by(compta, body: "Il manque le ticket du 12/08"))

    notification = Notification.last
    expect(notification.title).to include("compta@les4sources.be").and include("le rassemblement du")
    expect(notification.body).to eq("Il manque le ticket du 12/08")
  end

  # Un auteur qui a supprimé son commentaire reste dans la conversation : il a
  # participé, il doit savoir qu'on lui répond.
  it "garde dans la boucle l'auteur d'un commentaire supprimé" do
    comment_by(michael).soft_delete!(validate: false)

    described_class.call(comment_by(compta))

    expect(Notification.pluck(:recipient_id)).to eq([michael.id])
  end
end
