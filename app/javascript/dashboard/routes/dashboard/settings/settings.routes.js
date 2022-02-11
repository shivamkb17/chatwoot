import { frontendURL } from '../../../helper/URLHelper';
import account from './account/account.routes';
import billing from './billing/billing.routes';
import agent from './agents/agent.routes';
import canned from './canned/canned.routes';
import inbox from './inbox/inbox.routes';
import integrations from './integrations/integrations.routes';
import integrationapps from './integrationapps/integrations.routes';
import labels from './labels/labels.routes';
import profile from './profile/profile.routes';
import reports from './reports/reports.routes';
import campaigns from './campaigns/campaigns.routes';
import teams from './teams/teams.routes';
import attributes from './attributes/attributes.routes';
import automation from './automation/automation.routes';
import store from '../../../store';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings'),
      name: 'settings_home',
      roles: ['administrator', 'agent'],
      redirect: () => {
        if (store.getters.getCurrentRole === 'administrator') {
          return frontendURL('accounts/:accountId/settings/agents');
        }
        return frontendURL('accounts/:accountId/settings/canned-response');
      },
    },
    ...account.routes,
    ...billing.routes,
    ...agent.routes,
    ...canned.routes,
    ...inbox.routes,
    ...integrations.routes,
    ...labels.routes,
    ...profile.routes,
    ...reports.routes,
    ...teams.routes,
    ...campaigns.routes,
    ...integrationapps.routes,
    ...attributes.routes,
    ...automation.routes,
  ],
};
