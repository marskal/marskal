SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: folder_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.folder_state AS ENUM (
    'active',
    'dropped'
);


--
-- Name: import_batch_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.import_batch_status AS ENUM (
    'pending',
    'previewed',
    'applying',
    'applied',
    'failed'
);


--
-- Name: import_channel; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.import_channel AS ENUM (
    'file',
    'oauth'
);


--
-- Name: import_item_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.import_item_kind AS ENUM (
    'folder',
    'project',
    'task'
);


--
-- Name: task_state; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.task_state AS ENUM (
    'to_do',
    'done',
    'dropped'
);


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id bigint NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_attachments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_attachments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_attachments_id_seq OWNED BY public.active_storage_attachments.id;


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id bigint NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_blobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_blobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_blobs_id_seq OWNED BY public.active_storage_blobs.id;


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id bigint NOT NULL,
    blob_id bigint NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.active_storage_variant_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: active_storage_variant_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.active_storage_variant_records_id_seq OWNED BY public.active_storage_variant_records.id;


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_batches; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_batches (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    source character varying NOT NULL,
    channel public.import_channel DEFAULT 'file'::public.import_channel NOT NULL,
    status public.import_batch_status DEFAULT 'pending'::public.import_batch_status NOT NULL,
    stats jsonb DEFAULT '{}'::jsonb NOT NULL,
    error_message text,
    external_account character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: import_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.import_items (
    id uuid DEFAULT uuidv7() NOT NULL,
    import_batch_id uuid NOT NULL,
    user_id uuid NOT NULL,
    source character varying NOT NULL,
    kind public.import_item_kind NOT NULL,
    source_id character varying NOT NULL,
    project_folder_id uuid,
    project_id uuid,
    task_id uuid,
    extras jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: project_folders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.project_folders (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    name character varying NOT NULL,
    parent_id uuid,
    parent_path text[] DEFAULT '{}'::text[] NOT NULL,
    state public.folder_state DEFAULT 'active'::public.folder_state NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: projects; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.projects (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    title character varying NOT NULL,
    notes text,
    state public.task_state DEFAULT 'to_do'::public.task_state NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    project_folder_id uuid
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    ip_address character varying,
    user_agent character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tasks (
    id uuid DEFAULT uuidv7() NOT NULL,
    user_id uuid NOT NULL,
    title character varying NOT NULL,
    notes text,
    state public.task_state DEFAULT 'to_do'::public.task_state NOT NULL,
    inbox boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    project_id uuid
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT uuidv7() NOT NULL,
    email_address character varying NOT NULL,
    password_digest character varying NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_attachments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments ALTER COLUMN id SET DEFAULT nextval('public.active_storage_attachments_id_seq'::regclass);


--
-- Name: active_storage_blobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs ALTER COLUMN id SET DEFAULT nextval('public.active_storage_blobs_id_seq'::regclass);


--
-- Name: active_storage_variant_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records ALTER COLUMN id SET DEFAULT nextval('public.active_storage_variant_records_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: import_batches import_batches_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT import_batches_pkey PRIMARY KEY (id);


--
-- Name: import_items import_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT import_items_pkey PRIMARY KEY (id);


--
-- Name: project_folders project_folders_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_folders
    ADD CONSTRAINT project_folders_pkey PRIMARY KEY (id);


--
-- Name: projects projects_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT projects_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: tasks tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT tasks_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_import_batches_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_user_id ON public.import_batches USING btree (user_id);


--
-- Name: index_import_batches_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_batches_on_user_id_and_created_at ON public.import_batches USING btree (user_id, created_at);


--
-- Name: index_import_items_on_import_batch_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_import_batch_id ON public.import_items USING btree (import_batch_id);


--
-- Name: index_import_items_on_import_batch_id_and_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_import_batch_id_and_kind ON public.import_items USING btree (import_batch_id, kind);


--
-- Name: index_import_items_on_project_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_project_folder_id ON public.import_items USING btree (project_folder_id);


--
-- Name: index_import_items_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_project_id ON public.import_items USING btree (project_id);


--
-- Name: index_import_items_on_task_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_task_id ON public.import_items USING btree (task_id);


--
-- Name: index_import_items_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_import_items_on_user_id ON public.import_items USING btree (user_id);


--
-- Name: index_import_items_on_user_id_and_source_and_source_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_import_items_on_user_id_and_source_and_source_id ON public.import_items USING btree (user_id, source, source_id);


--
-- Name: index_project_folders_on_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_folders_on_parent_id ON public.project_folders USING btree (parent_id);


--
-- Name: index_project_folders_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_folders_on_user_id ON public.project_folders USING btree (user_id);


--
-- Name: index_project_folders_on_user_id_and_parent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_folders_on_user_id_and_parent_id ON public.project_folders USING btree (user_id, parent_id);


--
-- Name: index_project_folders_on_user_id_and_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_project_folders_on_user_id_and_state ON public.project_folders USING btree (user_id, state);


--
-- Name: index_projects_on_project_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_project_folder_id ON public.projects USING btree (project_folder_id);


--
-- Name: index_projects_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_user_id ON public.projects USING btree (user_id);


--
-- Name: index_projects_on_user_id_and_project_folder_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_user_id_and_project_folder_id ON public.projects USING btree (user_id, project_folder_id);


--
-- Name: index_projects_on_user_id_and_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_projects_on_user_id_and_state ON public.projects USING btree (user_id, state);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_tasks_on_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_project_id ON public.tasks USING btree (project_id);


--
-- Name: index_tasks_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_user_id ON public.tasks USING btree (user_id);


--
-- Name: index_tasks_on_user_id_and_inbox_and_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_user_id_and_inbox_and_state ON public.tasks USING btree (user_id, inbox, state);


--
-- Name: index_tasks_on_user_id_and_project_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_user_id_and_project_id ON public.tasks USING btree (user_id, project_id);


--
-- Name: index_tasks_on_user_id_and_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tasks_on_user_id_and_state ON public.tasks USING btree (user_id, state);


--
-- Name: index_users_on_email_address; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_address ON public.users USING btree (email_address);


--
-- Name: import_items fk_rails_015f8d125f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT fk_rails_015f8d125f FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: tasks fk_rails_02e851e3b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_02e851e3b7 FOREIGN KEY (project_id) REFERENCES public.projects(id);


--
-- Name: import_batches fk_rails_12f3440250; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_batches
    ADD CONSTRAINT fk_rails_12f3440250 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: tasks fk_rails_4d2a9e4d7e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_4d2a9e4d7e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: project_folders fk_rails_52d5e908b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_folders
    ADD CONSTRAINT fk_rails_52d5e908b8 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: project_folders fk_rails_70d7453b30; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.project_folders
    ADD CONSTRAINT fk_rails_70d7453b30 FOREIGN KEY (parent_id) REFERENCES public.project_folders(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: import_items fk_rails_804e55101d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT fk_rails_804e55101d FOREIGN KEY (import_batch_id) REFERENCES public.import_batches(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: import_items fk_rails_b22cbc769e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT fk_rails_b22cbc769e FOREIGN KEY (project_folder_id) REFERENCES public.project_folders(id);


--
-- Name: projects fk_rails_b872a6760a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_b872a6760a FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: import_items fk_rails_c8984e37db; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT fk_rails_c8984e37db FOREIGN KEY (task_id) REFERENCES public.tasks(id);


--
-- Name: import_items fk_rails_d3df598113; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.import_items
    ADD CONSTRAINT fk_rails_d3df598113 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: projects fk_rails_fbf93d1a3d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_fbf93d1a3d FOREIGN KEY (project_folder_id) REFERENCES public.project_folders(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260919010001'),
('20260919010000'),
('20260812100000'),
('20260812090000'),
('20260811214318'),
('20260811204336'),
('20260811204335');

