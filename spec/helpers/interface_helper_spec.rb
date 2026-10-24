require "rails_helper"

RSpec.describe InterfaceHelper, type: :helper do
  describe "#ui_avatar" do
    it "montre la photo de la fiche humain quand il y en a une (Michael 2026-10-24)" do
      human = double("Human", photo?: true, photo_url: "/uploads/human/photo/7/thumb_bene.jpg")

      html = helper.ui_avatar("Béné", human: human)

      expect(html).to include('src="/uploads/human/photo/7/thumb_bene.jpg"')
      expect(html).to include("ui-av-photo")
    end

    it "retombe sur les initiales sans photo" do
      html = helper.ui_avatar("Béné Dupont", human: double("Human", photo?: false))

      expect(html).to include(">BD</span>")
    end

    it "ne confond pas la teinte sable avec la petite taille" do
      name = ("a".."z").map { |c| "Nom #{c}" }.find { |n| n.sum % 5 == 4 }

      expect(helper.ui_avatar(name)).to include("ui-av-sand")
      expect(helper.ui_avatar(name)).not_to include("ui-av-s ")
    end
  end
end
