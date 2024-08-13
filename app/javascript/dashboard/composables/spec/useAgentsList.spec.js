import { ref } from 'vue';
import { describe, it, expect, vi, beforeEach } from 'vitest';
import { useAgentsList } from '../useAgentsList';
import { useStoreGetters } from 'dashboard/composables/store';
import { allAgentsData, formattedAgentsData } from './fixtures/agentFixtures';
import * as agentHelper from 'dashboard/helper/agentHelper';

vi.mock('dashboard/composables/store');
vi.mock('dashboard/helper/agentHelper');

describe('useAgentsList', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    agentHelper.getAgentsByUpdatedPresence.mockImplementation(agents => agents);
    agentHelper.getSortedAgentsByAvailability.mockReturnValue(
      formattedAgentsData.slice(1)
    );

    useStoreGetters.mockReturnValue({
      getCurrentUser: ref(allAgentsData[0]),
      getSelectedChat: ref({ inbox_id: 1, meta: { assignee: true } }),
      getCurrentAccountId: ref(1),
      'inboxAssignableAgents/getAssignableAgents': ref(() => allAgentsData),
    });
  });

  it('returns agentsList and assignableAgents', () => {
    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual(allAgentsData);
    expect(agentsList.value).toEqual([
      agentHelper.createNoneAgent,
      ...formattedAgentsData.slice(1),
    ]);
  });

  it('includes None agent when includeNoneAgent is true', () => {
    const { agentsList } = useAgentsList(true);

    expect(agentsList.value[0]).toEqual(agentHelper.createNoneAgent);
    expect(agentsList.value.length).toBe(formattedAgentsData.length);
  });

  it('excludes None agent when includeNoneAgent is false', () => {
    const { agentsList } = useAgentsList(false);

    expect(agentsList.value[0]).not.toEqual(agentHelper.createNoneAgent);
    expect(agentsList.value.length).toBe(formattedAgentsData.length - 1);
  });

  it('handles empty assignable agents', () => {
    useStoreGetters.mockReturnValue({
      ...useStoreGetters(),
      'inboxAssignableAgents/getAssignableAgents': ref(() => []),
    });
    agentHelper.getSortedAgentsByAvailability.mockReturnValue([]);

    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual([]);
    expect(agentsList.value).toEqual([agentHelper.createNoneAgent]);
  });

  it('handles missing inbox_id', () => {
    useStoreGetters.mockReturnValue({
      ...useStoreGetters(),
      getSelectedChat: ref({ meta: { assignee: true } }),
      'inboxAssignableAgents/getAssignableAgents': ref(() => []),
    });
    agentHelper.getSortedAgentsByAvailability.mockReturnValue([]);

    const { agentsList, assignableAgents } = useAgentsList();

    expect(assignableAgents.value).toEqual([]);
    expect(agentsList.value).toEqual([agentHelper.createNoneAgent]);
  });
});