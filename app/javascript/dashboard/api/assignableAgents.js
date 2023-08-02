/* global axios */
import ApiClient from './ApiClient';

class AssignableAgents extends ApiClient {
  constructor() {
    super('assignable_agents', { accountScoped: true });
  }

  get({ inboxIds, conversationIds }) {
    return axios.get(this.url, {
      params: { inbox_ids: inboxIds, conversation_ids: conversationIds },
    });
  }
}

export default new AssignableAgents();
