require "rails_helper"

# Issue #306 — le lien de connexion à usage unique des comptes Devise.
RSpec.describe UserLoginLink, type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(email: "steph@les4sources.be", password: "password123") }

  describe ".issue!" do
    it "retourne un jeton en clair et ne le stocke nulle part" do
      link, token = described_class.issue!(user)

      expect(token).to be_present
      expect(link.token_digest).not_to eq(token)
      expect(link.attributes.values.map(&:to_s)).not_to include(token)
      expect(described_class.where("token_digest LIKE ?", "%#{token}%")).to be_empty
    end

    it "pose une expiration à 15 minutes" do
      freeze_time do
        link, = described_class.issue!(user)

        expect(link.expires_at).to eq(15.minutes.from_now)
      end
    end

    # Un lien demandé deux fois ne doit pas laisser deux portes ouvertes.
    it "brûle les liens vivants précédents du même utilisateur" do
      ancien, ancien_token = described_class.issue!(user)
      described_class.issue!(user)

      expect(ancien.reload.consumed_at).to be_present
      expect(described_class.find_usable(ancien_token)).to be_nil
    end

    it "ne touche pas aux liens d'un AUTRE utilisateur" do
      autre = User.create!(email: "compta@les4sources.be", password: "password123")
      _, jeton_autre = described_class.issue!(autre)

      described_class.issue!(user)

      expect(described_class.find_usable(jeton_autre)).to be_present
    end
  end

  describe ".find_usable" do
    it "retrouve le lien pour un jeton correct" do
      link, token = described_class.issue!(user)

      expect(described_class.find_usable(token)).to eq(link)
    end

    it "rend nil pour un jeton inconnu" do
      described_class.issue!(user)

      expect(described_class.find_usable("n-importe-quoi")).to be_nil
    end

    it "rend nil pour un jeton vide — pas une exception" do
      expect(described_class.find_usable(nil)).to be_nil
      expect(described_class.find_usable("")).to be_nil
    end

    it "rend nil après expiration" do
      _, token = described_class.issue!(user)

      travel 16.minutes do
        expect(described_class.find_usable(token)).to be_nil
      end
    end

    it "rend nil après consommation — un lien ne sert qu'une fois" do
      link, token = described_class.issue!(user)
      link.consume!

      expect(described_class.find_usable(token)).to be_nil
    end
  end

  describe ".throttled?" do
    it "laisse passer en dessous de 5 émissions dans l'heure" do
      4.times { described_class.issue!(user) }

      expect(described_class.throttled?(user)).to be(false)
    end

    it "bloque à partir de 5 émissions dans l'heure" do
      5.times { described_class.issue!(user) }

      expect(described_class.throttled?(user)).to be(true)
    end

    # Brûler un lien ne remet pas le compteur à zéro : sinon, redemander un lien
    # dans la foulée contournerait le rate-limit.
    it "compte les liens déjà consommés" do
      5.times { described_class.issue!(user).first.consume! }

      expect(described_class.throttled?(user)).to be(true)
    end

    it "oublie un lien émis il y a plus d'une heure" do
      5.times { described_class.issue!(user) }
      described_class.where(user_id: user.id).update_all(created_at: 2.hours.ago)

      expect(described_class.throttled?(user)).to be(false)
    end

    it "refuse plutôt que d'émettre quand l'utilisateur est nil" do
      expect(described_class.throttled?(nil)).to be(true)
    end
  end

  describe "#consume!" do
    it "rend le lien inutilisable une seconde fois" do
      link, token = described_class.issue!(user)
      link.consume!

      expect(link).to be_consumed
      expect(described_class.find_usable(token)).to be_nil
    end
  end
end
