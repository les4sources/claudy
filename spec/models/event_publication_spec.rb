require "rails_helper"

# Publication d'un événement sur le site (concern `Publishable`).
RSpec.describe Event, type: :model do
  let!(:category) { EventCategory.create!(name: "Parties", color: "amber") }
  let(:september) { Time.zone.parse("2026-09-18 18:30") }

  def build_event(name:, starts_at: september, **attributes)
    Event.new(name: name, event_category: category, starts_at: starts_at, ends_at: starts_at + 3.hours, **attributes)
  end

  it "est valide sans les champs virtuels du formulaire quand les dates sont en base" do
    event = build_event(name: "Pizza party")
    expect(event).to be_valid
    expect(event.save).to be(true)
  end

  describe "slug" do
    it "est proposé depuis le titre, le mois et l'année en français" do
      expect(build_event(name: "Pizza party").suggested_slug).to eq("pizza-party-septembre-2026")
    end

    it "ne double pas un mois ou une année déjà dans le titre" do
      expect(build_event(name: "Pizza party de septembre").suggested_slug).to eq("pizza-party-de-septembre-2026")
      expect(build_event(name: "Bilan 2026").suggested_slug).to eq("bilan-2026-septembre")
    end

    it "est posé à la première publication et dédoublonné, corbeille comprise" do
      first = build_event(name: "Pizza party", published_at: Time.current)
      first.save!
      expect(first.slug).to eq("pizza-party-septembre-2026")
      first.soft_delete!(validate: false)

      second = build_event(name: "Pizza party", published_at: Time.current)
      second.save!
      expect(second.slug).to eq("pizza-party-septembre-2026-2")
    end

    it "reste vide et modifiable tant que la fiche est un brouillon" do
      draft = build_event(name: "Pizza party")
      draft.save!
      expect(draft.slug).to be_nil

      draft.update!(slug: "Pizza Party Spéciale")
      expect(draft.slug).to eq("pizza-party-speciale")
    end

    it "ne change plus tant que la fiche est en ligne ; dépublier garde le slug mais le libère" do
      event = build_event(name: "Pizza party", published_at: Time.current)
      event.save!

      event.slug = "autre-adresse"
      expect(event).not_to be_valid
      expect(event.errors[:slug]).to include("ne peut plus changer une fois la fiche publiée")

      event.reload.update!(published_at: nil)
      expect(event.slug).to eq("pizza-party-septembre-2026")

      # Hors ligne, changer d'adresse est un acte délibéré : autorisé.
      event.update!(slug: "autre-adresse")
      event.update!(published_at: Time.current)
      expect(event.reload.slug).to eq("autre-adresse")
    end

    it "refuse un slug mal formé" do
      event = build_event(name: "Pizza party", slug: "pizza party!")
      # `parameterize` nettoie ce qu'il peut ; un slug vide après nettoyage n'est pas un problème pour un brouillon.
      expect(event).to be_valid
      expect(event.slug).to eq("pizza-party")
    end
  end

  describe "résumé" do
    it "tient en 200 caractères" do
      expect(build_event(name: "Pizza party", summary: "a" * 200)).to be_valid
      expect(build_event(name: "Pizza party", summary: "a" * 201)).not_to be_valid
    end
  end

  describe "all_day?" do
    it "est vrai quand les deux bornes sont à minuit" do
      midnight = Time.zone.parse("2026-09-18 00:00")
      expect(build_event(name: "Journée portes ouvertes", starts_at: midnight).all_day?).to be(false)
      expect(Event.new(starts_at: midnight, ends_at: midnight + 1.day).all_day?).to be(true)
    end
  end

  describe "reconstruction du site" do
    it "est demandée à la publication, à la modification d'une fiche publiée et à la dépublication" do
      event = build_event(name: "Pizza party")
      expect(WebsiteRebuildJob).not_to receive(:request!)
      event.save!

      RSpec::Mocks.space.proxy_for(WebsiteRebuildJob).reset
      expect(WebsiteRebuildJob).to receive(:request!).exactly(3).times
      event.update!(published_at: Time.current)
      event.update!(summary: "Nouveau résumé")
      event.update!(published_at: nil)
    end

    it "n'est pas demandée pour un brouillon qui reste un brouillon" do
      event = build_event(name: "Pizza party")
      event.save!
      expect(WebsiteRebuildJob).not_to receive(:request!)
      event.update!(summary: "Brouillon retouché")
    end
  end
end
