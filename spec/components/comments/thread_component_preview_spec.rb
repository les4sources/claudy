require "rails_helper"

# La preview Lookbook est du code comme le reste : si elle casse, `/lookbook`
# casse, et personne ne s'en aperçoit avant d'y aller. On la rend ici.
RSpec.describe Comments::ThreadComponentPreview, type: :component do
  %i[empty with_comments with_error].each do |scenario|
    it "rend la preview « #{scenario} »" do
      expect { render_preview(scenario, from: described_class) }.not_to raise_error
    end
  end
end
