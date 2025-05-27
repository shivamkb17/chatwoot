import { shallowMount, mount } from '@vue/test-utils';
import Asterisk from './Asterisk.vue'; // Adjust path as necessary
import Vuex from 'vuex';
import Vuelidate from 'vuelidate'; // Import Vuelidate
import Vue from 'vue'; // Import Vue to install Vuelidate

// Apply Vuelidate to Vue
Vue.use(Vuelidate);

// Mock i18n
const $t = jest.fn(key => key); // Simple mock for $t

const createStore = (uiFlags = { isCreating: false }) => {
  return new Vuex.Store({
    modules: {
      inboxes: {
        namespaced: true,
        getters: {
          getUIFlags: () => uiFlags,
        },
        actions: {
          createChannel: jest.fn(),
        },
      },
    },
  });
};

const router = {
  replace: jest.fn(),
};

const mountComponent = (store, fullMount = false) => {
  const mountOptions = {
    store,
    mocks: {
      $t,
      $router: router, // Mock Vue Router
      // Mock Vuelidate's $v object. We will provide a basic structure.
      // For more complex validation testing, this mock might need to be more detailed
      // or we'd let Vuelidate initialize properly on the component.
      // For this component, Vuelidate is initialized via setup(), so we don't mock $v globally here.
    },
    stubs: {
      PageHeader: true, // Stub child components for shallower tests
      NextButton: { template: '<button type="submit"><slot/></button>' }, // Basic stub for button
    },
  };
  if (fullMount) {
    return mount(Asterisk, mountOptions);
  }
  return shallowMount(Asterisk, mountOptions);
};


describe('Asterisk.vue', () => {
  let store;

  beforeEach(() => {
    store = createStore();
    router.replace.mockClear();
    store.dispatch = jest.fn(() => Promise.resolve({ id: '123' })); // Mock dispatch to return a promise
  });

  it('renders all form fields correctly', () => {
    const wrapper = mountComponent(store, true); // Use full mount to find nested elements

    // Check for input fields by their expected placeholder or associated label text
    // (using $t mock, placeholder will be the key itself)
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.PORT.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.USERNAME.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[type="password"]').exists()).toBe(true); // Password field
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.WEBHOOK_URL.PLACEHOLDER"]').exists()).toBe(true);
    // New fields for outgoing calls
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CALLER_ID.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CONTEXT.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_EXTENSION.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_PRIORITY.PLACEHOLDER"]').exists()).toBe(true);
    expect(wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.PLACEHOLDER"]').exists()).toBe(true);

    expect(wrapper.findComponent({ name: 'NextButton' }).exists()).toBe(true);
  });

  it('allows user input into form fields', async () => {
    const wrapper = mountComponent(store, true);
    const channelNameInput = wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.PLACEHOLDER"]');
    await channelNameInput.setValue('My Asterisk Channel');
    expect(wrapper.vm.channelName).toBe('My Asterisk Channel');

    const hostInput = wrapper.find('input[placeholder="INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.PLACEHOLDER"]');
    await hostInput.setValue('asterisk.example.com');
    expect(wrapper.vm.host).toBe('asterisk.example.com');
  });

  it('shows validation messages for required fields if submitted empty', async () => {
    const wrapper = mountComponent(store, true); // Full mount to allow Vuelidate to attach
    await wrapper.find('form').trigger('submit.prevent');

    // Wait for Vuelidate to update the view
    await wrapper.vm.$nextTick();

    // Check for error messages (assuming .message class and specific error keys)
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PORT.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.USERNAME.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PASSWORD.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.WEBHOOK_URL.ERROR');
    // Validation messages for new fields
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CALLER_ID.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CONTEXT.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_EXTENSION.ERROR');
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_PRIORITY.ERROR');
    // For originate_channel_string, the error message key is different based on which validation failed (required vs format)
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.ERROR_REQUIRED');
  });

  it('shows validation message for originate_channel_string format if placeholder is missing', async () => {
    const wrapper = mountComponent(store, true);
    await wrapper.setData({
      originate_channel_string: 'PJSIP/mytrunk', // Missing {destination_number}
    });
    await wrapper.find('form').trigger('submit.prevent');
    await wrapper.vm.$nextTick();
    expect(wrapper.html()).toContain('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.ERROR_FORMAT');
  });


  it('dispatches createChannel action with correct payload on valid form submission', async () => {
    const wrapper = mountComponent(store, true);

    // Fill form data
    const formData = {
      channelName: 'Test Asterisk',
      host: 'test.host.com',
      port: '5060',
      username: 'testuser',
      password: 'testpassword',
      webhookUrl: 'http://testwebhook.com/hook',
      default_caller_id: '1800123123',
      default_context: 'from-chatwoot',
      default_extension: 's',
      default_priority: '1',
      originate_channel_string: 'PJSIP/{destination_number}@myendpoint',
    };
    await wrapper.setData(formData);

    // Trigger form submission
    await wrapper.find('form').trigger('submit.prevent');
    await wrapper.vm.$nextTick(); // Wait for Vuelidate and submit logic

    expect(store.dispatch).toHaveBeenCalledWith('inboxes/createChannel', {
      name: formData.channelName,
      channel: {
        type: 'asterisk',
        host: formData.host,
        port: formData.port,
        username: formData.username,
        password: formData.password,
        webhook_url: formData.webhookUrl,
        default_caller_id: formData.default_caller_id,
        default_context: formData.default_context,
        default_extension: formData.default_extension,
        default_priority: 1, // Ensure it's a number
        originate_channel_string: formData.originate_channel_string,
      },
    });
  });

  it('navigates to add agents page on successful channel creation', async () => {
    const wrapper = mountComponent(store, true);
    const formData = { // Fill with valid data
      channelName: 'Test Asterisk',
      host: 'test.host.com',
      port: '5060',
      username: 'testuser',
      password: 'testpassword',
      webhookUrl: 'http://testwebhook.com/hook',
      default_caller_id: '1800123123',
      default_context: 'from-chatwoot',
      default_extension: 's',
      default_priority: '1',
      originate_channel_string: 'PJSIP/{destination_number}@myendpoint',
    };
    await wrapper.setData(formData);

    await wrapper.find('form').trigger('submit.prevent');
    await wrapper.vm.$nextTick(); // for submit
    await wrapper.vm.$nextTick(); // for promise resolution if any extra ticks needed

    expect(router.replace).toHaveBeenCalledWith({
      name: 'settings_inboxes_add_agents',
      params: {
        page: 'new',
        inbox_id: '123', // Mocked response from createChannel action
      },
    });
  });

  it('shows error alert if createChannel action fails', async () => {
    // Override store dispatch to simulate failure
    store.dispatch = jest.fn(() => Promise.reject(new Error('Network Error')));
    const wrapper = mountComponent(store, true);
    const useAlertSpy = jest.spyOn(require('dashboard/composables'), 'useAlert');

    const formData = { // Fill with valid data
      channelName: 'Test Asterisk Fail',
      host: 'fail.host.com',
      port: '5061',
      username: 'failuser',
      password: 'failpassword',
      webhookUrl: 'http://failwebhook.com/hook',
      default_caller_id: '1800123123',
      default_context: 'from-chatwoot',
      default_extension: 's',
      default_priority: '1',
      originate_channel_string: 'PJSIP/{destination_number}@myendpoint',
    };
    await wrapper.setData(formData);

    await wrapper.find('form').trigger('submit.prevent');
    await wrapper.vm.$nextTick();
    await wrapper.vm.$nextTick();


    expect(useAlertSpy).toHaveBeenCalledWith('INBOX_MGMT.ADD.ASTERISK_CHANNEL.API.ERROR_MESSAGE');
    useAlertSpy.mockRestore(); // Clean up spy
  });

  it('shows loading state on button when creating channel', async () => {
    const storeWithLoading = createStore({ isCreating: true });
    const wrapper = mountComponent(storeWithLoading, true);

    // Access the NextButton component and check its props
    const nextButton = wrapper.findComponent({ name: 'NextButton' });
    // This depends on how NextButton internally handles `is-loading`.
    // If it's a direct prop that controls a class or attribute:
    expect(nextButton.props('isLoading')).toBe(true); // Assuming NextButton has an isLoading prop
  });
});

// Mock 'dashboard/composables' for useAlert
jest.mock('dashboard/composables', () => ({
  useAlert: jest.fn(),
}));
