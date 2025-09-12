<template>
  <div class="overlay" @click.self="close">
    <div class="modal">
      <header>
        <h2>{{ t('wiz.title') }}</h2>
        <button class="close-btn" @click="close">×</button>
      </header>
      <section class="content" v-if="!error && !loading">
        <h3 class="filename">wizexercise.txt</h3>
        <pre>{{ fileText }}</pre>
  <div class="path">{{ t('wiz.pathLabel') }}: <code>{{ containerPath }}</code></div>
      </section>
      <section v-else-if="loading" class="loading">{{ t('wiz.loading') }}</section>
      <section v-else class="error">{{ error }}</section>
      <footer>
        <button @click="close">{{ t('wiz.close') }}</button>
      </footer>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({ show: Boolean })
const emits = defineEmits(['close'])

const fileText = ref('')
const error = ref(null)
const loading = ref(true)

// Path inside container (Nginx serving static compiled app); source file not shipped unless copied.
// During dev (Vite), this is resolved from /src/assets.
  const containerPath = ref('')
const { t } = useI18n()

async function loadFile() {
  loading.value = true
  error.value = null
  try {
    const res = await fetch('/wizexercise.txt?cache=' + Date.now())
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    const raw = await res.text()
    const lines = raw.split(/\r?\n/)
    if (lines[0].startsWith('[container-path]')) {
      containerPath.value = lines[0].replace('[container-path]', '').trim()
      fileText.value = lines.slice(1).join('\n')
    } else {
      containerPath.value = '(no embedded path header)'
      fileText.value = raw
    }
  } catch (e) {
    error.value = 'Failed to load file: ' + e.message
  } finally {
    loading.value = false
  }
}

onMounted(loadFile)

function close() { emits('close') }
</script>

<style scoped>
.overlay { position: fixed; inset:0; background: rgba(0,0,0,0.5); display:flex; align-items:center; justify-content:center; z-index:1000; }
.modal { background:#fff; width: min(90%, 700px); max-height: 80vh; display:flex; flex-direction:column; border-radius:8px; box-shadow:0 4px 16px rgba(0,0,0,0.25); }
header { display:flex; justify-content:space-between; align-items:center; padding:1rem 1.25rem; border-bottom:1px solid #e2e8f0; }
header h2 { margin:0; font-size:1.1rem; }
.close-btn { background:transparent; border:none; font-size:1.5rem; line-height:1; cursor:pointer; }
.content { padding:1rem 1.25rem; overflow:auto; flex:1; }
pre { background:#f7fafc; padding:1rem; border-radius:6px; font-size:0.85rem; line-height:1.3; white-space:pre-wrap; word-break:break-word; }
.path { margin-top:0.75rem; font-size:0.75rem; color:#555; }
 .filename { margin:0 0 0.5rem 0; font-size:0.85rem; font-weight:600; color:#333; letter-spacing:0.5px; text-transform:uppercase; }
footer { padding:0.75rem 1.25rem; border-top:1px solid #e2e8f0; text-align:right; }
footer button { background:#007bff; color:#fff; border:none; padding:0.5rem 1rem; border-radius:4px; cursor:pointer; }
footer button:hover { background:#0056b3; }
.loading, .error { padding:1rem 1.25rem; }
.error { color:#d93025; }
</style>