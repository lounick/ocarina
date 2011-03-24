------------------------------------------------------------------------------
--                                                                          --
--                           OCARINA COMPONENTS                             --
--                                                                          --
--              OCARINA.BACKENDS.XTRATUM_CONF.PARTITION_TABLE               --
--                                                                          --
--                                 B o d y                                  --
--                                                                          --
--            Copyright (C) 2011, European Space Agency (ESA).              --
--                                                                          --
-- Ocarina  is free software;  you  can  redistribute  it and/or  modify    --
-- it under terms of the GNU General Public License as published by the     --
-- Free Software Foundation; either version 2, or (at your option) any      --
-- later version. Ocarina is distributed  in  the  hope  that it will be    --
-- useful, but WITHOUT ANY WARRANTY;  without even the implied warranty of  --
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General --
-- Public License for more details. You should have received  a copy of the --
-- GNU General Public License distributed with Ocarina; see file COPYING.   --
-- If not, write to the Free Software Foundation, 51 Franklin Street, Fifth --
-- Floor, Boston, MA 02111-1301, USA.                                       --
--                                                                          --
-- As a special exception,  if other files  instantiate  generics from this --
-- unit, or you link  this unit with other files  to produce an executable, --
-- this  unit  does not  by itself cause  the resulting  executable to be   --
-- covered  by the  GNU  General  Public  License. This exception does not  --
-- however invalidate  any other reasons why the executable file might be   --
-- covered by the GNU Public License.                                       --
--                                                                          --
--                 Ocarina is maintained by the Ocarina team                --
--                       (ocarina-users@listes.enst.fr)                     --
--                                                                          --
------------------------------------------------------------------------------

with Namet; use Namet;
with Utils; use Utils;

with Ocarina.ME_AADL;
with Ocarina.ME_AADL.AADL_Tree.Nodes;
with Ocarina.ME_AADL.AADL_Tree.Entities;
with Ocarina.ME_AADL.AADL_Instances.Nodes;
with Ocarina.ME_AADL.AADL_Instances.Nutils;
with Ocarina.ME_AADL.AADL_Instances.Entities;

with Ocarina.Backends.Utils;
with Ocarina.Instances.Queries;

with Ocarina.Backends.Messages;
with Ocarina.Backends.Properties;
with Ocarina.Backends.XML_Tree.Nodes;
with Ocarina.Backends.XML_Tree.Nutils;

package body Ocarina.Backends.Xtratum_Conf.Partition_Table is

   use Ocarina.ME_AADL;
   use Ocarina.ME_AADL.AADL_Instances.Nodes;
   use Ocarina.ME_AADL.AADL_Instances.Entities;

   use Ocarina.Instances.Queries;

   use Ocarina.Backends.Utils;
   use Ocarina.Backends.Messages;
   use Ocarina.Backends.Properties;
   use Ocarina.Backends.XML_Tree.Nutils;

   package ATN renames Ocarina.ME_AADL.AADL_Tree.Nodes;
   package ATE renames Ocarina.ME_AADL.AADL_Tree.Entities;
   package AIN renames Ocarina.ME_AADL.AADL_Instances.Nodes;
   package AINU renames Ocarina.ME_AADL.AADL_Instances.Nutils;
   package XTN renames Ocarina.Backends.XML_Tree.Nodes;

   procedure Visit_Architecture_Instance (E : Node_Id);
   procedure Visit_Component_Instance (E : Node_Id);
   procedure Visit_System_Instance (E : Node_Id);
   procedure Visit_Process_Instance (E : Node_Id);
   procedure Visit_Memory_Instance (E : Node_Id);
   procedure Visit_Processor_Instance (E : Node_Id);
   procedure Visit_Virtual_Processor_Instance (E : Node_Id);

   Current_System : Node_Id := No_Node;

   -----------
   -- Visit --
   -----------

   procedure Visit (E : Node_Id) is
   begin
      case Kind (E) is
         when K_Architecture_Instance =>
            Visit_Architecture_Instance (E);

         when K_Component_Instance =>
            Visit_Component_Instance (E);

         when others =>
            null;
      end case;
   end Visit;

   ---------------------------------
   -- Visit_Architecture_Instance --
   ---------------------------------

   procedure Visit_Architecture_Instance (E : Node_Id) is
   begin
      Visit (Root_System (E));
   end Visit_Architecture_Instance;

   ------------------------------
   -- Visit_Component_Instance --
   ------------------------------

   procedure Visit_Component_Instance (E : Node_Id) is
      Category : constant Component_Category
        := Get_Category_Of_Component (E);
   begin
      case Category is
         when CC_System =>
            Visit_System_Instance (E);

         when CC_Process =>
            Visit_Process_Instance (E);

         when CC_Processor =>
            Visit_Processor_Instance (E);

         when CC_Memory =>
            Visit_Memory_Instance (E);

         when CC_Virtual_Processor =>
            Visit_Virtual_Processor_Instance (E);

         when others =>
            null;
      end case;
   end Visit_Component_Instance;

   ----------------------------
   -- Visit_Process_Instance --
   ----------------------------

   procedure Visit_Process_Instance (E : Node_Id) is
      Partition_Node       : Node_Id;
      Base_Address_Value   : Unsigned_Long_Long;
      Byte_Count_Value     : Unsigned_Long_Long;
      Associated_Processor : Node_Id;
      Associated_Module    : Node_Id;
      Associated_Memory    : Node_Id;
      Physical_Areas_Node  : Node_Id;
      Temporal_Req_Node    : Node_Id;
      Port_Table_Node      : Node_Id;
      Port_Node            : Node_Id;
      Area_Node            : Node_Id;
      P                    : Node_Id;
      Q                    : Node_Id;
      S                    : Node_Id;
      F                    : Node_Id;
   begin
      Associated_Processor := Get_Bound_Processor (E);
      Associated_Memory := Get_Bound_Memory (E);
      Associated_Module :=
            Parent_Component
               (Parent_Subcomponent (Associated_Processor));

      --  Some checks on the model in order to make sure that
      --  everything is correctly defined.

      if Associated_Processor = No_Node then
         Display_Located_Error
            (AIN.Loc (E),
             "A partition has to be associated with one virtual processor.",
             Fatal => True);
      end if;

      if Associated_Memory = No_Node then
         Display_Located_Error
            (AIN.Loc (E),
             "A partition has to be associated with one memory.",
             Fatal => True);
      end if;

      if Associated_Module = No_Node then
         Display_Located_Error
            (AIN.Loc (E),
             "Unable to retrieve the module that executes this partition.",
             Fatal => True);
      end if;

      --  Create the main partition node that defines all partition
      --  requirements.

      Partition_Node := Make_XML_Node ("Partition");

      Set_Str_To_Name_Buffer ("id");
      P := Make_Defining_Identifier (Name_Find);
      Q := Copy_Node (Backend_Node (Identifier (Associated_Processor)));
      Append_Node_To_List
         (Make_Assignement (P, Q), XTN.Items (Partition_Node));

      Set_Str_To_Name_Buffer ("name");
      P := Make_Defining_Identifier (Name_Find);
      Get_Name_String
         (To_Lower
            (Display_Name
            (Identifier (Parent_Subcomponent (E)))));
      Q := Make_Defining_Identifier (Name_Find);
      Append_Node_To_List
         (Make_Assignement (P, Q), XTN.Items (Partition_Node));

      Set_Str_To_Name_Buffer ("console");
      P := Make_Defining_Identifier (Name_Find);
      Set_Str_To_Name_Buffer ("Uart");
      Q := Make_Defining_Identifier (Name_Find);
      Append_Node_To_List
         (Make_Assignement (P, Q), XTN.Items (Partition_Node));

      --  Create the PhysicalAreasNode associated with the partition.
      --  It maps the requirements of the memory component associated
      --  with the partition.
      Physical_Areas_Node := Make_XML_Node ("PhysicalMemoryAreas");

      Append_Node_To_List (Physical_Areas_Node,
                           XTN.Subitems (Partition_Node));

      Area_Node := Make_XML_Node ("Area");

      Base_Address_Value :=
         Get_Integer_Property (Associated_Memory, "base_address");
      Byte_Count_Value :=
         Get_Integer_Property (Associated_Memory, "byte_count");
      Set_Str_To_Name_Buffer ("start");
      P := Make_Defining_Identifier (Name_Find);
      Set_Str_To_Name_Buffer ("0x");
      Add_Str_To_Name_Buffer
         (Unsigned_Long_Long'Image (Base_Address_Value));

      Q := Make_Defining_Identifier (Remove_Char (Name_Find, ' '));

      Append_Node_To_List
         (Make_Assignement (P, Q), XTN.Items (Area_Node));

      Set_Str_To_Name_Buffer ("size");
      P := Make_Defining_Identifier (Name_Find);
      Byte_Count_Value := Byte_Count_Value / 1024;
      Set_Str_To_Name_Buffer
         (Unsigned_Long_Long'Image (Byte_Count_Value));
      Add_Str_To_Name_Buffer ("KB");
      Q := Make_Defining_Identifier (Remove_Char (Name_Find, ' '));

      Append_Node_To_List
         (Make_Assignement (P, Q), XTN.Items (Area_Node));

      Append_Node_To_List (Area_Node,
                           XTN.Subitems (Physical_Areas_Node));

      --  Create the TemporalRequirements node associated with the partition.
      --  It maps the requirements of the virtual processor component
      --  associated with the partition.

      Temporal_Req_Node := Make_XML_Node ("TemporalRequirements");

      declare
         Slots             : constant Time_Array
                           := Get_POK_Slots (Associated_Module);
         Slots_Allocation  : constant List_Id
                           := Get_POK_Slots_Allocation (Associated_Module);
         Duration          : Unsigned_Long_Long := 0;
         Major_Frame       : constant Unsigned_Long_Long
                           := To_Milliseconds
                              (Get_POK_Major_Frame (Associated_Module));
         Part              : Node_Id;
      begin
         S := ATN.First_Node (Slots_Allocation);
         for I in Slots'Range loop

            Part := ATE.Get_Referenced_Entity (S);

            if Part = Associated_Processor then
               Duration := Duration + To_Milliseconds (Slots (I));
            end if;

            S := ATN.Next_Node (S);
         end loop;
         Set_Str_To_Name_Buffer ("duration");
         P := Make_Defining_Identifier (Name_Find);
         Set_Str_To_Name_Buffer
            (Unsigned_Long_Long'Image (Duration));
         Add_Str_To_Name_Buffer ("ms");
         Q := Make_Defining_Identifier (Remove_Char (Name_Find, ' '));

         Append_Node_To_List
            (Make_Assignement (P, Q), XTN.Items (Temporal_Req_Node));

         Set_Str_To_Name_Buffer ("period");
         P := Make_Defining_Identifier (Name_Find);
         Set_Str_To_Name_Buffer
            (Unsigned_Long_Long'Image (Major_Frame));
         Add_Str_To_Name_Buffer ("ms");
         Q := Make_Defining_Identifier (Remove_Char (Name_Find, ' '));

         Append_Node_To_List
            (Make_Assignement (P, Q), XTN.Items (Temporal_Req_Node));

      end;

      Append_Node_To_List
         (Temporal_Req_Node, XTN.Subitems (Partition_Node));

      --  Now, handle the ports of the partition.
      if Has_Ports (E) then
         Port_Table_Node := Make_XML_Node ("PortTable");

         F := First_Node (Features (E));
         while Present (F) loop
            if Kind (F) = K_Port_Spec_Instance then

               if not Is_Data (F) then
                  Display_Located_Error
                     (AIN.Loc (F),
                      "Pure events ports are not allowed.",
                      Fatal => True);
               end if;

               if Is_In (F) and then Is_Out (F) then
                  Display_Located_Error
                     (AIN.Loc (F),
                      "in/out ports are not allowed.",
                      Fatal => True);
               end if;

               Port_Node := Make_XML_Node ("Port");

               Set_Str_To_Name_Buffer ("name");
               P := Make_Defining_Identifier (Name_Find);

               Get_Name_String (Display_Name (Identifier (F)));
               Q := Make_Defining_Identifier (To_Lower (Name_Find));
               Append_Node_To_List
                  (Make_Assignement (P, Q), XTN.Items (Port_Node));

               Set_Str_To_Name_Buffer ("type");
               P := Make_Defining_Identifier (Name_Find);

               if Is_Data (F) and then not Is_Event (F) then
                  Set_Str_To_Name_Buffer ("sampling");
               else
                  Set_Str_To_Name_Buffer ("queuing");
               end if;

               Q := Make_Defining_Identifier (Name_Find);
               Append_Node_To_List
                  (Make_Assignement (P, Q), XTN.Items (Port_Node));

               Set_Str_To_Name_Buffer ("direction");
               P := Make_Defining_Identifier (Name_Find);

               if Is_In (F) then
                  Set_Str_To_Name_Buffer ("destination");
               else
                  Set_Str_To_Name_Buffer ("source");
               end if;

               Q := Make_Defining_Identifier (Name_Find);
               Append_Node_To_List
                  (Make_Assignement (P, Q), XTN.Items (Port_Node));

               Append_Node_To_List
                  (Port_Node, XTN.Subitems (Port_Table_Node));
            end if;
            F := Next_Node (F);
         end loop;

         Append_Node_To_List (Port_Table_Node, XTN.Subitems (Partition_Node));
      end if;

      Append_Node_To_List
         (Partition_Node, XTN.Subitems (Current_XML_Node));
   end Visit_Process_Instance;

   ---------------------------
   -- Visit_System_Instance --
   ---------------------------

   procedure Visit_System_Instance (E : Node_Id) is
      S                    : Node_Id;
      U                    : Node_Id;
      R                    : Node_Id;
   begin
      U := XTN.Unit (Backend_Node (Identifier (E)));
      R := XTN.Node (Backend_Node (Identifier (E)));

      Current_System := E;

      Current_XML_Node := XTN.Root_Node (XTN.XML_File (U));

      Push_Entity (U);
      Push_Entity (R);

      if not AINU.Is_Empty (Subcomponents (E)) then
         S := First_Node (Subcomponents (E));
         while Present (S) loop
         --  Visit the component instance corresponding to the
         --  subcomponent S.
            if AINU.Is_Processor (Corresponding_Instance (S)) then
               Visit (Corresponding_Instance (S));
            end if;
            S := Next_Node (S);
         end loop;
      end if;

      Pop_Entity;
      Pop_Entity;
   end Visit_System_Instance;

   ------------------------------
   -- Visit_Processor_Instance --
   ------------------------------

   procedure Visit_Processor_Instance (E : Node_Id) is
      S                    : Node_Id;
      Partition_Table_Node : Node_Id;
   begin
      --  Create the main PartitionTable node.

      Partition_Table_Node := Make_XML_Node ("PartitionTable");

      Append_Node_To_List (Partition_Table_Node,
                           XTN.Subitems (Current_XML_Node));

      Current_XML_Node := Partition_Table_Node;

      if not AINU.Is_Empty (Subcomponents (E)) then
         S := First_Node (Subcomponents (E));
         while Present (S) loop
         --  Visit the component instance corresponding to the
         --  subcomponent S.

            Visit (Corresponding_Instance (S));
            S := Next_Node (S);
         end loop;
      end if;

   end Visit_Processor_Instance;

   --------------------------------------
   -- Visit_Virtual_Processor_Instance --
   --------------------------------------

   procedure Visit_Virtual_Processor_Instance (E : Node_Id) is
      S           : Node_Id;
   begin
      if not AINU.Is_Empty (Subcomponents (Current_System)) then
         S := First_Node (Subcomponents (Current_System));
         while Present (S) loop
         --  Visit the component instance corresponding to the
         --  subcomponent S.
            if AINU.Is_Process (Corresponding_Instance (S)) and then
               Get_Bound_Processor (Corresponding_Instance (S)) = E then
               Visit (Corresponding_Instance (S));
            end if;
            S := Next_Node (S);
         end loop;
      end if;

      if not AINU.Is_Empty (Subcomponents (E)) then
         S := First_Node (Subcomponents (E));
         while Present (S) loop
         --  Visit the component instance corresponding to the
         --  subcomponent S.

            Visit (Corresponding_Instance (S));
            S := Next_Node (S);
         end loop;
      end if;
   end Visit_Virtual_Processor_Instance;

   ---------------------------
   -- Visit_Memory_Instance --
   ---------------------------

   procedure Visit_Memory_Instance (E : Node_Id) is
      pragma Unreferenced (E);
   begin
      null;
   end Visit_Memory_Instance;

end Ocarina.Backends.Xtratum_Conf.Partition_Table;