-- Doctor Service Schema

CREATE SCHEMA IF NOT EXISTS doctors;

CREATE TABLE IF NOT EXISTS doctors.doctors (
    id TEXT PRIMARY KEY,  -- BetterAuth nanoid (not UUID)
    name VARCHAR(255) NOT NULL,
    specialisation VARCHAR(255),
    contact VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctors.time_slots (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    doctor_id TEXT REFERENCES doctors.doctors(id),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ NOT NULL,
    status VARCHAR(50) DEFAULT 'available',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS doctors.consultations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    appointment_id UUID UNIQUE,  -- one consultation per appointment
    doctor_id TEXT REFERENCES doctors.doctors(id),
    patient_id TEXT NOT NULL,
    notes TEXT,
    diagnosis TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_consultations_patient ON doctors.consultations(patient_id);
CREATE INDEX IF NOT EXISTS idx_consultations_doctor ON doctors.consultations(doctor_id);
