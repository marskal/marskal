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
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
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
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


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
-- Name: tasks fk_rails_02e851e3b7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tasks
    ADD CONSTRAINT fk_rails_02e851e3b7 FOREIGN KEY (project_id) REFERENCES public.projects(id);


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
-- Name: projects fk_rails_b872a6760a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.projects
    ADD CONSTRAINT fk_rails_b872a6760a FOREIGN KEY (user_id) REFERENCES public.users(id);


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
('20260812100000'),
('20260812090000'),
('20260811214318'),
('20260811204336'),
('20260811204335');

