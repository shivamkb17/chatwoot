<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required, numeric, url } from '@vuelidate/validators';
import router from '../../../../index';
import PageHeader from '../../SettingsSubPageHeader.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    PageHeader,
    NextButton,
  },
  setup() {
    return { v$: useVuelidate() };
  },
  data() {
    return {
      channelName: '',
      host: '',
      port: '',
      username: '',
      password: '',
      webhookUrl: '',
      // New attributes for outgoing calls
      default_caller_id: '',
      default_context: '',
      default_extension: 's', // Default to 's' as it's common
      default_priority: '1', // Default to '1'
      originate_channel_string: '', // e.g., PJSIP/{destination_number}@endpoint
    };
  },
  computed: {
    ...mapGetters({
      uiFlags: 'inboxes/getUIFlags',
    }),
  },
  validations: {
    channelName: { required },
    host: { required },
    port: { required, numeric },
    username: { required },
    password: { required },
    webhookUrl: { required, url },
    // Validations for new outgoing call attributes
    default_caller_id: { required },
    default_context: { required },
    default_extension: { required },
    default_priority: { required, numeric },
    originate_channel_string: {
      required,
      mustContainDestinationNumber: value =>
        value.includes('{destination_number}'),
    },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const asteriskChannel = await this.$store.dispatch('inboxes/createChannel', {
          name: this.channelName,
          channel: {
            type: 'asterisk',
            host: this.host,
            port: this.port,
            username: this.username,
            password: this.password,
            webhook_url: this.webhookUrl,
            // New outgoing call attributes
            default_caller_id: this.default_caller_id,
            default_context: this.default_context,
            default_extension: this.default_extension,
            default_priority: parseInt(this.default_priority, 10), // Ensure it's a number
            originate_channel_string: this.originate_channel_string,
          },
        });

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: asteriskChannel.id,
          },
        });
      } catch (error) {
        useAlert(this.$t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.API.ERROR_MESSAGE'));
      }
    },
  },
};
</script>

<template>
  <div
    class="border border-n-weak bg-n-solid-1 rounded-t-lg border-b-0 h-full w-full p-6 col-span-6 overflow-auto"
  >
    <PageHeader
      :header-title="$t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.TITLE')"
      :header-content="$t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DESC')"
    />
    <form
      class="flex flex-wrap flex-col mx-0"
      @submit.prevent="createChannel()"
    >
      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.channelName.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.LABEL') }}
          <input
            v-model.trim="channelName"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.PLACEHOLDER')
            "
            @blur="v$.channelName.$touch"
          />
          <span v-if="v$.channelName.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.CHANNEL_NAME.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.host.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.LABEL') }}
          <input
            v-model.trim="host"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.PLACEHOLDER')
            "
            @blur="v$.host.$touch"
          />
          <span v-if="v$.host.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.HOST.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.port.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PORT.LABEL') }}
          <input
            v-model.trim="port"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PORT.PLACEHOLDER')
            "
            @blur="v$.port.$touch"
          />
          <span v-if="v$.port.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PORT.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.username.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.USERNAME.LABEL') }}
          <input
            v-model.trim="username"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.USERNAME.PLACEHOLDER')
            "
            @blur="v$.username.$touch"
          />
          <span v-if="v$.username.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.USERNAME.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.password.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PASSWORD.LABEL') }}
          <input
            v-model="password"
            type="password"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PASSWORD.PLACEHOLDER')
            "
            @blur="v$.password.$touch"
          />
          <span v-if="v$.password.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.PASSWORD.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.webhookUrl.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.WEBHOOK_URL.LABEL') }}
          <input
            v-model.trim="webhookUrl"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.WEBHOOK_URL.PLACEHOLDER')
            "
            @blur="v$.webhookUrl.$touch"
          />
          <span v-if="v$.webhookUrl.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.WEBHOOK_URL.ERROR')
          }}</span>
        </label>
      </div>

      <!-- Fields for Outgoing Call Configuration -->
      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.default_caller_id.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CALLER_ID.LABEL') }}
          <input
            v-model.trim="default_caller_id"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CALLER_ID.PLACEHOLDER')
            "
            @blur="v$.default_caller_id.$touch"
          />
          <span v-if="v$.default_caller_id.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CALLER_ID.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.default_context.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CONTEXT.LABEL') }}
          <input
            v-model.trim="default_context"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CONTEXT.PLACEHOLDER')
            "
            @blur="v$.default_context.$touch"
          />
          <span v-if="v$.default_context.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_CONTEXT.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.default_extension.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_EXTENSION.LABEL') }}
          <input
            v-model.trim="default_extension"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_EXTENSION.PLACEHOLDER')
            "
            @blur="v$.default_extension.$touch"
          />
          <span v-if="v$.default_extension.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_EXTENSION.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.default_priority.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_PRIORITY.LABEL') }}
          <input
            v-model.trim="default_priority"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_PRIORITY.PLACEHOLDER')
            "
            @blur="v$.default_priority.$touch"
          />
          <span v-if="v$.default_priority.$error" class="message">{{
            $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.DEFAULT_PRIORITY.ERROR')
          }}</span>
        </label>
      </div>

      <div class="flex-shrink-0 flex-grow-0 w-full">
        <label :class="{ error: v$.originate_channel_string.$error }">
          {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.LABEL') }}
          <input
            v-model.trim="originate_channel_string"
            type="text"
            :placeholder="
              $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.PLACEHOLDER')
            "
            @blur="v$.originate_channel_string.$touch"
          />
          <p class="help-text">
            {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.HELP_TEXT') }}
          </p>
          <span v-if="v$.originate_channel_string.$error && v$.originate_channel_string.required.$invalid" class="message">
            {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.ERROR_REQUIRED') }}
          </span>
          <span v-if="v$.originate_channel_string.$error && !v$.originate_channel_string.required.$invalid && v$.originate_channel_string.mustContainDestinationNumber.$invalid" class="message">
            {{ $t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.ORIGINATE_CHANNEL_STRING.ERROR_FORMAT') }}
          </span>
        </label>
      </div>

      <div class="w-full mt-4">
        <NextButton
          :is-loading="uiFlags.isCreating"
          type="submit"
          solid
          blue
          :label="$t('INBOX_MGMT.ADD.ASTERISK_CHANNEL.SUBMIT_BUTTON')"
        />
      </div>
    </form>
  </div>
</template>
<style lang="scss" scoped>
// Add any specific styles if needed, similar to Api.vue or other channel components
.flex-shrink-0 {
  margin-bottom: var(--space-normal); // Equivalent to my-2 or similar spacing
}

label {
  font-weight: var(--font-weight-medium); // Ensure labels are styled consistently
}

input[type="text"],
input[type="password"] {
  width: 100%; // Make inputs take full width of their container
  padding: var(--space-small) var(--space-one); // Consistent padding
  border-radius: var(--border-radius-medium); // Consistent border radius
  border: 1px solid var(--s-200); // Consistent border color

  &:focus {
    border-color: var(--w-500); // Highlight focus
  }

  &::placeholder {
    color: var(--s-400); // Style placeholder text
  }
}

.message {
  color: var(--r-500); // Error message color
  font-size: var(--font-size-small); // Error message size
}

.help-text {
  font-size: var(--font-size-small);
  color: var(--s-500);
  margin-top: var(--space-smaller);
}
</style>
