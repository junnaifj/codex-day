import importlib.util,json,pathlib,sqlite3,tempfile,unittest
spec=importlib.util.spec_from_file_location('summary',pathlib.Path(__file__).resolve().parents[1]/'codex-day/scripts/summarize.py'); summary=importlib.util.module_from_spec(spec);spec.loader.exec_module(summary)
class ConversationTests(unittest.TestCase):
 def test_reads_archived_and_ignores_tool_messages_without_writing(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);log=root/'chat.jsonl'
   log.write_text('\n'.join(json.dumps({'type':'response_item','payload':{'type':'message','role':role,'content':[{'type':'input_text','text':text}]}}) for role,text in [('user','Please draft report'),('assistant','Draft completed'),('tool','SECRET TOOL OUTPUT')]))
   db=root/'state_5.sqlite';c=sqlite3.connect(db);c.execute('create table threads(id,title,rollout_path,archived,agent_path,updated_at)');c.execute('insert into threads values(?,?,?,?,?,?)',('a','Report',str(log),1,None,1));c.commit();c.close()
   before=db.read_bytes();chats,unreadable=summary.conversations(root)
   self.assertEqual(before,db.read_bytes());self.assertEqual(unreadable,0);self.assertTrue(chats[0]['archived']);self.assertEqual(len(chats[0]['messages']),2)
 def test_missing_transcript_is_reported(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);c=sqlite3.connect(root/'state_5.sqlite');c.execute('create table threads(id,title,rollout_path,archived,agent_path,updated_at)');c.execute('insert into threads values(?,?,?,?,?,?)',('a','Missing',str(root/'missing'),0,None,1));c.commit();c.close()
   chats,unreadable=summary.conversations(root);self.assertEqual(unreadable,1);self.assertEqual(chats[0]['messages'],[])


class OfflineExtractionTests(unittest.TestCase):
 def test_completion_cancellation_code_and_untrusted_metadata(self):
  chat={'id':'a','title':'Project','messages':[{'text':'- [ ] Prepare report\n- [ ] Book room\n```\n- [ ] Ignore code example\n```'}, {'text':'- [x] Prepare report\nCancelled: Book room\nTODO: Send draft 2026-09-20'}]}
  tasks=summary.extract(chat)
  self.assertEqual([t['title'] for t in tasks],['Send draft 2026-09-20']);self.assertEqual(tasks[0]['date'],'2026-09-20')
 def test_no_date_is_not_assigned_to_today_and_ids_stable(self):
  chat={'id':'a','title':'Project','messages':[{'text':'## Next steps\n- Review draft\n\nFinished already.'}]}
  tasks=summary.extract(chat);self.assertEqual(len(tasks),1);self.assertIsNone(tasks[0]['date']);self.assertEqual(tasks,summary.extract(chat))
 def test_daily_cache_does_not_rescan_or_touch_user_tasks(self):
  with tempfile.TemporaryDirectory() as d:
   root=pathlib.Path(d);out=root/'suggestions.json';today=summary.datetime.date.today().isoformat();out.write_text(json.dumps({'updatedDay':today,'tasks':[]}));before=out.stat().st_mtime_ns
   self.assertEqual(summary.write_daily(root/'nonexistent',out)['tasks'],[]);self.assertEqual(out.stat().st_mtime_ns,before)
