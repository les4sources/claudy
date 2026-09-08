require "rails_helper"

# Epic #242, phase 1 — le commentaire polymorphe.
RSpec.describe Comment do
  let(:user) { User.create!(email: "auteur@les4sources.be", password: "password123") }
  let(:gathering) do
    Gathering.create!(name: "Réunion du collectif",
                      gathering_category: GatheringCategory.create!(name: "Collectif", color: "emerald"),
                      starts_at: Time.current, ends_at: 1.hour.from_now)
  end

  def build_comment(**attrs)
    described_class.new({ commentable: gathering, author: user, body: "Bonjour" }.merge(attrs))
  end

  it "se pose sur un rassemblement" do
    expect(build_comment).to be_valid
  end

  it "refuse un type qui n'est pas dans la liste blanche" do
    comment = build_comment
    comment.commentable_type = "User"

    expect(comment).not_to be_valid
    expect(comment.errors[:commentable_type]).to be_present
  end

  it "refuse un corps vide" do
    expect(build_comment(body: "")).not_to be_valid
    expect(build_comment(body: "   ")).not_to be_valid
    expect(build_comment(body: "<div><br></div>")).not_to be_valid
  end

  it "se supprime en douceur : la ligne reste, le fil ne la montre plus" do
    comment = build_comment.tap(&:save!)

    comment.soft_delete!(validate: false)

    expect(described_class.count).to eq(0)
    expect(described_class.with_deleted { described_class.count }).to eq(1)
  end

  describe "#editable_by?" do
    let(:comment) { build_comment.tap(&:save!) }
    let(:other) { User.create!(email: "autre@les4sources.be", password: "password123") }

    it "autorise son auteur" do
      expect(comment).to be_editable_by(user)
    end

    it "refuse un autre porteur" do
      other.update!(human: Human.create!(name: "Porteur"))

      expect(comment).not_to be_editable_by(other)
    end

    it "autorise un admin global" do
      expect(comment).to be_editable_by(other)
    end

    it "refuse un visiteur sans session" do
      expect(comment).not_to be_editable_by(nil)
    end
  end

  it "donne au fil un identifiant DOM stable, par type et par objet" do
    expect(described_class.thread_dom_id(gathering)).to eq("comments-thread-gathering-#{gathering.id}")
  end

  it "nomme son auteur par le membre d'équipe lié, sinon par son email" do
    expect(build_comment.author_label).to eq("auteur@les4sources.be")

    user.update!(human: Human.create!(name: "Michael Hulet"))
    expect(build_comment.author_label).to eq("Michael Hulet")
  end

  it "se lit dans l'ordre chronologique" do
    first  = build_comment(body: "un").tap { |c| c.save!; c.update_column(:created_at, 2.days.ago) }
    second = build_comment(body: "deux").tap(&:save!)

    expect(gathering.comments.chronological.to_a).to eq([first, second])
  end
end
