import { describe, expect, it } from 'vitest'
import { displayName, initials, kg, timeAgo } from './format'
import { fitWithin } from './image'
import { sizesFor } from './constants'

describe('timeAgo', () => {
  const now = Date.parse('2026-10-18T12:00:00Z')
  it('is relative when recent', () => {
    expect(timeAgo('2026-10-18T11:59:50Z', now)).toBe('just now')
    expect(timeAgo('2026-10-18T11:30:00Z', now)).toBe('30m ago')
    expect(timeAgo('2026-10-18T10:00:00Z', now)).toBe('2h ago')
    expect(timeAgo('2026-10-16T12:00:00Z', now)).toBe('2d ago')
  })
})

describe('names', () => {
  it('falls back to "Loop member"', () => {
    expect(displayName(null)).toBe('Loop member')
    expect(displayName('  ')).toBe('Loop member')
    expect(initials('Jordan Park')).toBe('JP')
  })
})

describe('kg', () => {
  it('keeps precision for small numbers', () => {
    expect(kg(0.44)).toBe('0.44')
    expect(kg(61.54)).toBe('61.5')
  })
})

describe('fitWithin', () => {
  it('caps the longest side at 1600 and keeps the aspect ratio', () => {
    expect(fitWithin(4000, 3000)).toEqual({ width: 1600, height: 1200 })
    expect(fitWithin(3000, 4000)).toEqual({ width: 1200, height: 1600 })
  })
  it('never upscales', () => {
    expect(fitWithin(800, 600)).toEqual({ width: 800, height: 600 })
  })
})

describe('sizesFor', () => {
  it('follows the contract vocabulary', () => {
    expect(sizesFor('tops')).toEqual(['XS', 'S', 'M', 'L', 'XL', 'XXL'])
    expect(sizesFor('shoes')).toContain('9.5')
    expect(sizesFor('shoes')[0]).toBe('5')
    expect(sizesFor('shoes').at(-1)).toBe('14')
    expect(sizesFor('bags')).toEqual(['One size'])
    expect(sizesFor('bottoms')).toContain('32')
  })
})
