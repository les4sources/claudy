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

  describe "nombre de repas" do
    it "vaut 5 par défaut — ce que prépare une session ordinaire" do
      expect(session.meals_count).to eq(5)
    end

    it "refuse zéro repas — ce n'est pas une session, c'est une saisie inachevée" do
      expect(described_class.new(cooked_on: Date.current, meals_count: 0)).not_to be_valid
    end

    it "refuse un nombre négatif de repas" do
      expect(described_class.new(cooked_on: Date.current, meals_count: -1)).not_to be_valid
    end
  end

  # Le nom de plat a été retiré de la saisie : un batch cooking prépare plusieurs
  # plats d'un coup, et Steph les annonce sur Slack. Une session se nomme donc
  # toujours par sa date, même si la colonne `label` porte encore une valeur.
  it "se nomme toujours par sa date" do
    expect(session.title).to eq("Batch cooking du 12/09/2026")
    expect(session(label: "Chili").title).to eq("Batch cooking du 12/09/2026")
  end

  describe "personnes et portions servies" do
    it "tient le total à jour depuis les lignes de service — personnes × repas" do
      seance = session(meals_count: 5)
      seance.servings.create!(member_account: compte, people: 3)

      expect(seance.reload.total_portions).to eq(15)
    end

    it "recompte après suppression d'une ligne" do
      seance = session
      ligne = seance.servings.create!(member_account: compte, people: 3)
      ligne.destroy!
      seance.save!

      expect(seance.reload.total_portions).to eq(0)
    end

    # Le piège de l'issue #307 : corriger le nombre de repas APRÈS coup ne doit
    # laisser aucune ligne périmée derrière lui.
    it "recompte quand le seul nombre de repas change" do
      seance = session(meals_count: 5)
      seance.servings.create!(member_account: compte, people: 3)

      seance.update!(meals_count: 4)

      expect(seance.reload.total_portions).to eq(12)
    end

    it "distingue les personnes servies des portions servies" do
      seance = session(meals_count: 5)
      seance.servings.create!(member_account: compte, people: 3)

      expect(seance.people_served).to eq(3)
      expect(seance.portions_served).to eq(15)
    end

    it "refuse zéro personne servie" do
      expect { session.servings.create!(member_account: compte, people: 0) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    it "refuse de servir deux fois le même compte sur une session" do
      seance = session
      seance.servings.create!(member_account: compte, people: 3)

      expect { seance.servings.create!(member_account: compte, people: 2) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end

    # Dérivée, pas stockée : rien à réécrire en base quand les repas changent.
    it "dérive les portions d'une ligne du nombre de repas de la session" do
      seance = session(meals_count: 5)
      ligne = seance.servings.create!(member_account: compte, people: 3)

      expect(ligne.portions).to eq(15)

      seance.update!(meals_count: 4)

      expect(ligne.reload.portions).to eq(12)
      expect(ligne.people).to eq(3)
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
      seance.servings.create!(member_account: compte, people: 3)
      seance.soft_delete!

      expect(described_class.with_deleted { described_class.find(seance.id) }.servings.count).to eq(1)
    end
  end
end
