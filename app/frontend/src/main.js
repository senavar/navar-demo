import { createApp } from 'vue'
import { createI18n } from 'vue-i18n'
import App from './App.vue'

// Import translation files
import en from './locales/en.json'
import es from './locales/es.json'

// Detect browser language or default to 'en'
const userLang = navigator.language.split('-')[0] || 'en';

const i18n = createI18n({
  legacy: false, // Use Vue 3 Composition API
  locale: userLang,
  fallbackLocale: 'en',
  messages: {
    en,
    es
  }
})

const app = createApp(App)
app.use(i18n) // Use the i18n plugin
app.mount('#app')