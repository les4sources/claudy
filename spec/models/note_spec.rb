# == Schema Information
#
# Table name: notes
#
#  id           :bigint           not null, primary key
#  body         :text
#  color        :string
#  date         :date
#  deleted_at   :datetime
#  external_ref :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
# Indexes
#
#  index_notes_on_external_ref_unique_live  (external_ref) UNIQUE WHERE ((deleted_at IS NULL) AND (external_ref IS NOT NULL))
#
require 'rails_helper'

RSpec.describe Note, type: :model do
  def build_note(attrs = {})
    Note.new({ body: "Grand ménage du gîte", date: Date.new(2026, 9, 11) }.merge(attrs))
  end

  describe "type de note (color)" do
    it "accepte les couleurs déclarées dans TYPES" do
      Note::TYPES.each_key do |color|
        expect(build_note(color: color)).to be_valid
      end
    end

    it "refuse une couleur inconnue" do
      note = build_note(color: "chartreuse")

      expect(note).not_to be_valid
      expect(note.errors[:color]).to be_present
    end

    # Des notes d'avant cette issue vivent en base sans type.
    it "accepte une couleur absente" do
      expect(build_note(color: nil)).to be_valid
    end

    it "traite une couleur vide comme une absence de type" do
      note = build_note(color: "")

      expect(note).to be_valid
      expect(note.color).to be_nil
    end
  end

  describe "#type_label" do
    it "rend le libellé de la couleur" do
      expect(build_note(color: "orange").type_label).to eq("Pizza party")
      expect(build_note(color: "yellow").type_label).to eq("Nettoyages")
    end

    it "rend nil sur une couleur inconnue ou vide" do
      expect(Note.new(color: "chartreuse").type_label).to be_nil
      expect(build_note(color: nil).type_label).to be_nil
    end
  end

  describe "external_ref" do
    it "refuse deux notes vivantes portant la même référence" do
      build_note(external_ref: "tranchesdevie-order-1234").save!
      doublon = build_note(external_ref: "tranchesdevie-order-1234")

      expect(doublon).not_to be_valid
      expect(doublon.errors[:external_ref]).to be_present
    end

    # L'unicité ne vaut que sur les notes vivantes : une note retirée du
    # calendrier libère sa référence, sinon l'appelant ne pourrait jamais la
    # reposer.
    it "laisse reposer la référence d'une note supprimée en douceur" do
      build_note(external_ref: "tranchesdevie-order-1234").save!
      Note.find_by(external_ref: "tranchesdevie-order-1234").soft_delete!(validate: false)

      expect(build_note(external_ref: "tranchesdevie-order-1234")).to be_valid
    end

    it "laisse plusieurs notes sans référence coexister" do
      build_note.save!

      expect(build_note).to be_valid
    end
  end
end
