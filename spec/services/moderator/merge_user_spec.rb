require "rails_helper"

RSpec.describe Moderator::MergeUser, type: :service do
  let!(:keep_user) { create(:user) }
  let!(:delete_user) { create(:user) }
  let(:delete_user_id) { delete_user.id }
  let(:admin) { create(:user, :super_admin) }

  describe "#merge" do
    let(:article) { create(:article, user: delete_user) }
    let(:comment) { create(:comment, user: delete_user) }
    let(:reaction) { create(:reaction, user: delete_user, category: "readinglist") }
    let(:article_reaction) { create(:reaction, reactable: article, category: "readinglist") }
    let(:related_records) { [article, comment, reaction, article_reaction] }

    before { sidekiq_perform_enqueued_jobs }

    it "deletes delete_user_id and keeps keep_user" do
      sidekiq_perform_enqueued_jobs do
        described_class.call_merge(admin: admin, keep_user: keep_user, delete_user_id: delete_user.id)
      end
      expect(User.find_by(id: delete_user_id)).to be_nil
      expect(User.find_by(id: keep_user.id)).not_to be_nil
    end

    it "updates documents in Elasticsearch" do
      related_records
      drain_all_sidekiq_jobs
      expect(article.elasticsearch_doc.dig("_source", "user", "id")).to eq(delete_user_id)
      expect(comment.elasticsearch_doc.dig("_source", "user", "id")).to eq(delete_user_id)
      expect(reaction.elasticsearch_doc.dig("_source", "user_id")).to eq(delete_user_id)
      expect(article_reaction.elasticsearch_doc.dig("_source", "reactable", "user", "id")).to eq(delete_user_id)

      sidekiq_perform_enqueued_jobs do
        described_class.call_merge(admin: admin, keep_user: keep_user, delete_user_id: delete_user.id)
      end
      drain_all_sidekiq_jobs
      expect(article.reload.elasticsearch_doc.dig("_source", "user", "id")).to eq(keep_user.id)
      expect(comment.reload.elasticsearch_doc.dig("_source", "user", "id")).to eq(keep_user.id)
      expect(reaction.reload.elasticsearch_doc.dig("_source", "user_id")).to eq(keep_user.id)
      expect(article_reaction.reload.elasticsearch_doc.dig("_source", "reactable", "user", "id")).to eq(keep_user.id)
    end
  end
end
