export type PostcodeStatus = 'pending' | 'valid' | 'invalid' | 'failed' | 'rate_limited';
export type EntityType = 'region' | 'regional_unit' | 'municipality' | 'community' | 'settlement';
export type ReviewStatus = 'accepted' | 'unresolved' | 'review_required';
export interface Postcode { postcode: string; status: PostcodeStatus; last_error_category: string | null; last_error_message: string | null; completed_at: string | null }
export interface Street { id: number; postcode: string; name: string; odd_start: string | null; odd_end: string | null; even_start: string | null; even_end: string | null }
export interface Location { postcode: string; latitude: number | null; longitude: number | null; local_area: string | null; municipal_unit_id: number | null; community_id: number | null; municipality_id: number | null }
export interface LibraryExport { validPostcodes: number; streets: number; locations: number; output: string }
export type FieldKind = 'text' | 'number' | 'json' | 'enum' | 'foreign';
export interface Field { name: string; kind?: FieldKind; nullable?: boolean; references?: string; values?: readonly string[]; readonly?: boolean }
export interface Table { name: string; primaryKey: string; fields: readonly Field[]; label: string }
