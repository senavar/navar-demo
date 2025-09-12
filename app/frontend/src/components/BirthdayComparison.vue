<script setup>
import { computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = defineProps({
  birthdays: {
    type: Array,
    required: true
  }
})

const { t } = useI18n()

const comparisons = computed(() => {
  if (props.birthdays.length < 2) {
    return []
  }

  const results = []
  // Create pairs of birthdays to compare
  for (let i = 0; i < props.birthdays.length; i++) {
    for (let j = i + 1; j < props.birthdays.length; j++) {
      const personA = props.birthdays[i]
      const personB = props.birthdays[j]

      const dateA = new Date(personA.year, personA.month - 1, personA.day)
      const dateB = new Date(personB.year, personB.month - 1, personB.day)

      // Ensure dateA is the earlier date
      const [olderPerson, youngerPerson, olderDate, youngerDate] =
        dateA < dateB ? [personA, personB, dateA, dateB] : [personB, personA, dateB, dateA]

      const diffMilliseconds = youngerDate - olderDate
      // Use a more accurate average for days in a year
      const diffDays = Math.floor(diffMilliseconds / (1000 * 60 * 60 * 24))
      
      const years = Math.floor(diffDays / 365.25)
      const remainingDaysAfterYears = Math.floor(diffDays % 365.25)
      // Use a more accurate average for days in a month
      const months = Math.floor(remainingDaysAfterYears / 30.44) 
      const days = Math.floor(remainingDaysAfterYears % 30.44)

      results.push({
        id: `${olderPerson.id}-${youngerPerson.id}`,
        olderName: olderPerson.name,
        youngerName: youngerPerson.name,
        years,
        months,
        days
      })
    }
  }
  return results
})

function formatDifference(years, months, days) {
  const parts = []
  if (years > 0) parts.push(t('comparison.years', { count: years }))
  if (months > 0) parts.push(t('comparison.months', { count: months }))
  if (days > 0) parts.push(t('comparison.days', { count: days }))
  // Handle cases where the difference is less than a day
  if (parts.length === 0) return t('comparison.sameDay')
  return parts.join(', ')
}
</script>

<template>
  <div class="comparison-container">
    <h2>{{ t('comparison.title') }}</h2>
    <div v-if="comparisons.length > 0" class="comparison-list">
      <div v-for="comp in comparisons" :key="comp.id" class="comparison-item">
        <p>
          <strong>{{ comp.olderName }}</strong> {{ t('comparison.isOlderThan') }} <strong>{{ comp.youngerName }}</strong> {{ t('comparison.by') }} {{ formatDifference(comp.years, comp.months, comp.days) }}.
        </p>
      </div>
    </div>
    <div v-else class="placeholder">
      <p>{{ t('comparison.selectTwo') }}</p>
    </div>
  </div>
</template>

<style scoped>
.comparison-container {
  padding: 1.5rem;
  background-color: #f8f9fa;
  border-radius: 8px;
  border: 1px solid #e9ecef;
  height: 100%;
}

h2 {
  margin-top: 0;
  margin-bottom: 1rem;
  color: #343a40;
  font-size: 1.5rem;
  border-bottom: 2px solid #007bff;
  padding-bottom: 0.5rem;
}

.comparison-list {
  display: flex;
  flex-direction: column;
  gap: 1rem;
}

.comparison-item {
  background-color: #fff;
  padding: 1rem;
  border-radius: 6px;
  box-shadow: 0 2px 4px rgba(0,0,0,0.05);
}

.comparison-item p {
  margin: 0;
  line-height: 1.6;
}

.placeholder {
  text-align: center;
  padding: 2rem;
  color: #6c757d;
}
</style>