require "rails_helper"

# Epic #25 — Phase 2 (comptes porteurs)
RSpec.describe Humans::CreateAccountService do
  describe "#run" do
    it "crée un User lié au Human et déclenche l'invitation par défaut" do
      human = Human.create!(name: "Alice Porteuse", email: "alice@example.com")
      service = described_class.new(human: human)

      expect { expect(service.run).to be(true) }.to change(User, :count).by(1)

      expect(human.reload.user).to be_present
      expect(human.user.email).to eq("alice@example.com")
      # send_reset_password_instructions horodate la demande d'invitation
      expect(human.user.reset_password_sent_at).to be_present
    end

    it "n'envoie pas d'invitation quand send_invitation: false" do
      human = Human.create!(name: "Bob Porteur", email: "bob@example.com")
      service = described_class.new(human: human, send_invitation: false)

      expect { expect(service.run).to be(true) }.to change(User, :count).by(1)
      expect(human.reload.user.reset_password_sent_at).to be_nil
    end

    it "échoue si le Human n'a pas d'email" do
      human = Human.create!(name: "Sans Email")
      service = described_class.new(human: human)

      expect { expect(service.run).to be(false) }.not_to change(User, :count)
      expect(service.error_message).to match(/email/i)
      expect(human.reload.user).to be_nil
    end

    it "échoue si le Human a déjà un compte" do
      human = Human.create!(name: "Déjà Compte", email: "deja@example.com")
      User.create!(email: "deja@example.com", password: "password123", human: human)
      service = described_class.new(human: human)

      expect(service.run).to be(false)
      expect(service.error_message).to match(/déjà/i)
    end

    it "échoue si un User existe déjà avec cette adresse email" do
      User.create!(email: "taken@example.com", password: "password123")
      human = Human.create!(name: "Email Pris", email: "taken@example.com")
      service = described_class.new(human: human)

      expect { expect(service.run).to be(false) }.not_to change(User, :count)
      expect(service.error_message).to match(/existe déjà/i)
    end
  end
end
