require "rails_helper"

# Rôles d'accès (2026-10-09) : ce que chaque rôle ouvre, et comment plusieurs
# rôles s'additionnent.
RSpec.describe Access do
  describe ".level" do
    it "donne tout au Sourcier, y compris ce qui n'est attribué à aucun rôle" do
      expect(described_class.level(%w[sourcier], :full)).to eq(:write)
      expect(described_class.level(%w[sourcier], :accounting)).to eq(:write)
    end

    it "ouvre le calendrier et la carte en lecture seule au Kid, et rien d'autre" do
      expect(described_class.level(%w[kid], :calendar)).to eq(:read)
      expect(described_class.level(%w[kid], :map)).to eq(:read)
      expect(described_class.level(%w[kid], :events)).to be_nil
      expect(described_class.level(%w[kid], :full)).to be_nil
    end

    it "ouvre les événements et activités à la Communication" do
      expect(described_class.level(%w[communication], :events)).to eq(:write)
      expect(described_class.level(%w[communication], :accounting)).to be_nil
    end

    it "ouvre comptes et comptabilité à l'Administratif" do
      expect(described_class.level(%w[administratif], :accounting)).to eq(:write)
      expect(described_class.level(%w[administratif], :accounts)).to eq(:write)
      expect(described_class.level(%w[administratif], :map)).to be_nil
    end

    it "additionne les droits de plusieurs rôles, en gardant le plus fort" do
      roles = %w[kid communication]
      expect(described_class.level(roles, :map)).to eq(:read)
      expect(described_class.level(roles, :events)).to eq(:write)
      expect(described_class.level(roles, :calendar)).to eq(:read)
    end

    it "ouvre l'espace personnel à tout compte qui a un rôle, pas à un compte sans rôle" do
      expect(described_class.level(%w[kid], :everyone)).to eq(:write)
      expect(described_class.level([], :everyone)).to be_nil
      expect(described_class.level([], :calendar)).to be_nil
    end

    it "ignore un rôle inconnu" do
      expect(described_class.level(%w[pirate], :full)).to be_nil
    end
  end

  describe "User" do
    it "refuse un rôle inconnu" do
      user = User.new(email: "x@example.com", password: "password123", access_roles: %w[pirate])
      expect(user).not_to be_valid
      expect(user.errors[:access_roles]).to be_present
    end

    it "nettoie les cases vides et les doublons du formulaire" do
      user = User.create!(email: "y@example.com", password: "password123", access_roles: ["", "kid", "kid"])
      expect(user.access_roles).to eq(%w[kid])
    end

    it "naît sans rôle hors des specs (défaut de la base)" do
      expect(User.column_defaults["access_roles"]).to eq([])
    end

    it "retrouve les comptes d'un rôle" do
      kid = User.create!(email: "kid@example.com", password: "password123", access_roles: %w[kid])
      User.create!(email: "com@example.com", password: "password123", access_roles: %w[communication])
      expect(User.with_access_role("kid")).to contain_exactly(kid)
    end
  end
end
