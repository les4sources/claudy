require "rails_helper"

# Epic #348, phase 11 — les fils de commentaires de la carte.
RSpec.describe MapComment, type: :model do
  let(:alice) { User.create!(email: "alice-carte@les4sources.be", password: "password123") }
  let(:bob) { User.create!(email: "bob-carte@les4sources.be", password: "password123") }
  let(:carol) { User.create!(email: "carol-carte@les4sources.be", password: "password123") }
  let(:layer) { MapLayer.for_kind(:comments) }
  let(:point) do
    layer.map_features.create!(feature_kind: "comment", geometry: { "type" => "Point", "coordinates" => [4.9, 50.34] })
  end
  let!(:root) { point.map_comments.create!(author: alice, body: "  La clôture est cassée ici  ") }

  it "exige un texte, nettoyé des espaces" do
    expect(root.body).to eq("La clôture est cassée ici")
    expect(point.map_comments.new(author: bob, body: "  ", parent: root)).not_to be_valid
  end

  it "n'accepte qu'un fil par point" do
    other_root = point.map_comments.new(author: bob, body: "Autre fil")
    expect(other_root).not_to be_valid
    expect(other_root.errors[:base].join).to include("déjà son fil")
  end

  it "garde un fil plat : on ne répond qu'au premier message, du même point" do
    reply = root.reply!(author: bob, body: "Je passe demain")
    nested = point.map_comments.new(author: carol, body: "Réponse à la réponse", parent: reply)
    expect(nested).not_to be_valid

    other_point = layer.map_features.create!(feature_kind: "comment",
                                              geometry: { "type" => "Point", "coordinates" => [4.91, 50.34] })
    stray = other_point.map_comments.new(author: carol, body: "Mauvais point", parent: root)
    expect(stray).not_to be_valid
  end

  it "rend le fil dans l'ordre, racine d'abord, d'où qu'on le lise" do
    first = root.reply!(author: bob, body: "Je passe demain")
    second = first.reply!(author: alice, body: "Merci !")

    expect(second.parent).to eq(root)
    expect(first.root).to eq(root)
    expect(first.thread.to_a).to eq([root, first, second])
    expect(root.thread.map(&:body)).to eq(["La clôture est cassée ici", "Je passe demain", "Merci !"])
  end

  it "compte parmi les participants l'auteur d'un message supprimé" do
    reply = root.reply!(author: bob, body: "Je passe demain")
    root.reply!(author: alice, body: "Merci !")
    reply.remove!

    expect(root.participants).to contain_exactly(alice, bob)
    expect(root.thread.map(&:author)).to eq([alice, alice])
  end

  describe "résolution" do
    it "se pose sur la racine, d'où qu'on l'appelle, puis se lève" do
      reply = root.reply!(author: bob, body: "Réparée")
      expect(reply.resolve!(by: bob)).to be(true)

      expect(root.reload.resolved_at).to be_present
      expect(reply.reload.resolved_at).to be_nil
      expect(reply.resolved?).to be(true)
      expect(reply.resolve!(by: bob)).to be(false)

      reply.reopen!
      expect(root.reload.resolved_at).to be_nil
    end

    it "refuse une date de résolution sur une réponse" do
      reply = root.reply!(author: bob, body: "Réparée")
      reply.resolved_at = Time.current
      expect(reply).not_to be_valid
    end
  end

  describe "#remove!" do
    it "retire une réponse seule" do
      reply = root.reply!(author: bob, body: "Je passe demain")
      reply.remove!

      expect(root.reload.thread.to_a).to eq([root])
      expect(MapFeature.exists?(point.id)).to be(true)
    end

    it "retire la racine avec tout le fil et son point" do
      root.reply!(author: bob, body: "Je passe demain")
      root.remove!

      expect(MapComment.where(map_feature_id: point.id)).to be_empty
      expect(MapComment.with_deleted { MapComment.where(map_feature_id: point.id).count }).to eq(2)
      expect(MapFeature.exists?(point.id)).to be(false)
    end
  end

  it "donne au point sa bulle : nombre de messages et état résolu" do
    root.reply!(author: bob, body: "Je passe demain")
    root.resolve!(by: bob)

    props = MapFeature.includes(:map_comments).find(point.id).as_geojson[:properties]
    expect(props).to include(feature_kind: "comment", comments_count: 2, resolved: true)
  end
end
