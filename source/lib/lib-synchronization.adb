--  lib-synchronization.adb: Synchronization primitives and such.
--  Copyright (C) 2021 streaksu
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.

with Lib.Messages;
with Lib.Panic;
with Lib.Atomic; use Lib.Atomic;
with Arch;
with Arch.Snippets;

package body Lib.Synchronization with SPARK_Mode => Off is
   function Is_Locked (Semaphore : aliased Binary_Semaphore) return Boolean is
   begin
      return Atomic_Load_8 (Semaphore.Is_Locked'Address, Mem_Seq_Cst) /= 0;
   end Is_Locked;

   procedure Seize (Semaphore : aliased in out Binary_Semaphore) is
      Did_Seize : Boolean;
   begin
<<Retry_Lock>>
      Try_Seize (Semaphore, Did_Seize);
      if Did_Seize then
         return;
      end if;

      --  Do a rough wait until the lock is free for cache-locality.
      --  https://en.wikipedia.org/wiki/Test_and_test-and-set
      for I in 1 .. 50000000 loop
         if Atomic_Load_8 (Semaphore.Is_Locked'Address, Mem_Relaxed) = 0 then
            goto Retry_Lock;
         end if;
         Arch.Snippets.Pause;
      end loop;

      Lib.Messages.Put ("Deadlock at address: ");
      Lib.Messages.Put (Semaphore.Caller);
      Lib.Messages.Put_Line ("");
      Lib.Panic.Hard_Panic ("Deadlocked!");
   end Seize;

   procedure Release (Semaphore : aliased in out Binary_Semaphore) is
   begin
      Atomic_Clear (Semaphore.Is_Locked'Address, Mem_Release);
   end Release;

   procedure Try_Seize
      (Semaphore : aliased in out Binary_Semaphore;
       Did_Lock  : out Boolean)
   is
   begin
      if Atomic_Test_And_Set (Semaphore.Is_Locked'Address, Mem_Acquire) then
         Did_Lock := False;
      else
         Semaphore.Caller := Get_Caller_Address (0);
         Did_Lock := True;
      end if;
   end Try_Seize;
end Lib.Synchronization;
