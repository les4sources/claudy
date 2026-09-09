require "rails_helper"

# Epic #246 — la session de batch cooking et ses deux listes.
RSpec.describe BatchCookingSession, type: :model do
  let(:household) { Household.create!(name: "Chevêche", kind: "resident") }
  let(:compte) { MemberAccount.create!(kind: "household", household: household, name: "Chevêche") }
  let(:stephanie) { Human.create!(name: "Stéphanie") }

  def session(attrs = {})
    described_class.create!({ cooked_on: Date.new(2026, 9, 12) }.merge(attrs))
  end

  it "exige une date" do
    expect(described_class.new).not_to be_valid
  end

  it "se nomme toute seule quand aucun libellé n'est donné" do
    expect(session.title).to eq("Batch cooking du 12/09/2026")
    expect(session(label: "Chili").title).to eq("Chili")
  end

  describe "portions servies" do
    it "tient le total à jour depuis les lignes de service" do
      seance = session
      seance.servings.create!(member_account: compte, portions: 3)

      expect(seance.reload.total_portions).to eq(3)
    end

    it "recompte après suppression d'une ligne" do
      seance = session
      ligne = seance.servings.create!(member_account: compte, portions: 3)
      ligne.destroy!
      seance.save!

      expect(seance.reload.total_portions).to eq(0)
    end

    it "refuse zéro portion servie" do
      expect { session.servings.create!(member_account: compte, portions: 0) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuse de servir deux fois le même compte sur une session" do
      seance = session
      seance.servings.create!(member_account: compte, portions: 3)

      expect { seance.servings.create!(member_account: compte, portions: 2) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe "cuisiniers" do
    it "accepte zéro portion — un coup de main sans part" do
      seance = session
      expect(seance.cooks.create!(human: stephanie, portions: 0)).to be_persisted
    end

    it "refuse un nombre négatif de portions" do
      expect { session.cooks.create!(human: stephanie, portions: -1) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "accepte une demi-portion — cinq portions pour deux cuisiniers" do
      cuisinier = session.cooks.create!(human: stephanie, portions: 2.5)

      expect(cuisinier.reload.portions).to eq(2.5)
    end

    it "refuse deux fois la même personne sur une session" do
      seance = session
      seance.cooks.create!(human: stephanie, portions: 5)

      expect { seance.cooks.create!(human: stephanie, portions: 1) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "retrouve le nom d'un cuisinier parti — Human est scopé sur les actifs" do
      cuisinier = session.cooks.create!(human: stephanie, portions: 5)
      stephanie.update_column(:status, "inactive")

      expect(cuisinier.reload.human_name).to eq("Stéphanie")
    end
  end

  describe ".even_split" do
    it "répartit à parts égales" do
      expect(described_class.even_split(10, 2)).to eq([5, 5])
    end

    it "partage au millième plutôt que de perdre une demi-portion" do
      expect(described_class.even_split(5, 2).map(&:to_f)).to eq([2.5, 2.5])
    end

    it "donne le reliquat aux premiers, et la somme retombe sur le total" do
      parts = described_class.even_split(7, 3)

      expect(parts.map(&:to_f)).to eq([2.334, 2.333, 2.333])
      expect(parts.sum).to eq(7)
    end

    it "ne divise pas par zéro cuisinier" do
      expect(described_class.even_split(5, 0)).to eq([])
    end
  end

  describe "suppression douce" do
    it "garde les lignes de service — la session doit rester relisable" do
      seance = session
      seance.servings.create!(member_account: compte, portions: 3)
      seance.soft_delete!

      expect(described_class.with_deleted { described_class.find(seance.id) }.servings.count).to eq(1)
    end
  end
end
